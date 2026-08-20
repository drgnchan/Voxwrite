import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/runtime_settings.dart';
import '../application/voice_session_controller.dart';
import '../domain/voice_session.dart';
import '../infrastructure/platform/global_shortcut_bridge.dart';
import '../infrastructure/platform/platform_overlay_bridge.dart';

class ShortcutCoordinator extends ConsumerStatefulWidget {
  const ShortcutCoordinator({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<ShortcutCoordinator> createState() =>
      _ShortcutCoordinatorState();
}

class _ShortcutCoordinatorState extends ConsumerState<ShortcutCoordinator> {
  final GlobalShortcutBridge _bridge = GlobalShortcutBridge();
  final PlatformOverlayBridge _overlay = PlatformOverlayBridge();
  StreamSubscription<GlobalShortcutEvent>? _subscription;
  Timer? _retryTimer;
  bool _subscribed = false;
  bool _connecting = false;
  bool _accessibilityPermissionPrompted = false;
  bool _inputMonitoringPermissionPrompted = false;
  String? _permissionNotice;

  @override
  void dispose() {
    _retryTimer?.cancel();
    _subscription?.cancel();
    unawaited(_bridge.setSessionActive(false));
    super.dispose();
  }

  Future<void> _setSubscribed(bool enabled) async {
    if (!enabled) {
      _retryTimer?.cancel();
      _retryTimer = null;
      await _subscription?.cancel();
      _subscription = null;
      _subscribed = false;
      _connecting = false;
      _accessibilityPermissionPrompted = false;
      _inputMonitoringPermissionPrompted = false;
      _permissionNotice = null;
      await _bridge.setSessionActive(false);
      return;
    }
    if (_subscribed || _connecting) return;

    _connecting = true;
    debugPrint('VoxWriteShortcut(Dart): checking global permissions');
    try {
      final accessibilityTrusted = _accessibilityPermissionPrompted
          ? await _bridge.hasAccessibilityPermission()
          : await _bridge.requestAccessibilityPermission();
      _accessibilityPermissionPrompted = true;
      debugPrint(
        'VoxWriteShortcut(Dart): accessibility trusted=$accessibilityTrusted',
      );
      if (!mounted || !_shortcutShouldBeEnabled) return;
      if (!accessibilityTrusted) {
        await _showPermissionNotice(
          code: 'accessibility',
          title: '需要辅助功能权限',
          detail: '在系统设置 → 隐私与安全性 → 辅助功能中允许 VoxWrite',
        );
        _scheduleRetry();
        return;
      }

      final inputMonitoringTrusted = _inputMonitoringPermissionPrompted
          ? await _bridge.hasInputMonitoringPermission()
          : await _bridge.requestInputMonitoringPermission();
      _inputMonitoringPermissionPrompted = true;
      debugPrint(
        'VoxWriteShortcut(Dart): input monitoring trusted='
        '$inputMonitoringTrusted',
      );
      if (!mounted || !_shortcutShouldBeEnabled) return;
      if (!inputMonitoringTrusted) {
        await _showPermissionNotice(
          code: 'inputMonitoring',
          title: '需要输入监控权限',
          detail: '允许 VoxWrite 监听其他 App 中的 Fn；授权后请重新打开 VoxWrite',
        );
        _scheduleRetry();
        return;
      }

      if (_permissionNotice != null) {
        _permissionNotice = null;
        await _overlay.hide();
      }

      debugPrint('VoxWriteShortcut(Dart): subscribing to native events');
      _subscription = _bridge.events().listen(
        _handleEvent,
        onError: (Object _) {
          _subscribed = false;
          _subscription = null;
          _scheduleRetry();
        },
        onDone: () {
          _subscribed = false;
          _subscription = null;
          _scheduleRetry();
        },
      );
      _subscribed = true;
      await _syncBackfillSetting();
    } catch (error, stackTrace) {
      debugPrint('VoxWriteShortcut(Dart): setup failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      _scheduleRetry();
    } finally {
      _connecting = false;
    }
  }

  Future<void> _syncBackfillSetting() async {
    final enabled =
        ref.read(runtimeSettingsProvider).value?.waylandBackfill ?? false;
    await _bridge.setWaylandBackfill(enabled);
  }

  bool get _shortcutShouldBeEnabled =>
      (Platform.isMacOS || Platform.isWindows || Platform.isLinux) &&
      (ref.read(runtimeSettingsProvider).value?.globalShortcutEnabled ?? false);

  Future<void> _showPermissionNotice({
    required String code,
    required String title,
    required String detail,
  }) async {
    if (_permissionNotice == code) return;
    _permissionNotice = code;
    await _overlay.show(title: title, detail: detail, kind: 'failed');
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    if (!mounted || !_shortcutShouldBeEnabled) return;
    _retryTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) unawaited(_setSubscribed(true));
    });
  }

  void _cancelActiveSession() {
    final phase = ref.read(voiceSessionProvider).phase;
    if (phase == VoiceSessionPhase.shortcutPreview ||
        phase == VoiceSessionPhase.recording ||
        phase == VoiceSessionPhase.processing) {
      unawaited(ref.read(voiceSessionProvider.notifier).reset());
    }
  }

  void _handleEvent(GlobalShortcutEvent event) {
    final controller = ref.read(voiceSessionProvider.notifier);
    switch (event.type) {
      case GlobalShortcutEventType.functionDown:
        unawaited(controller.shortcutDown());
      case GlobalShortcutEventType.functionUp:
        unawaited(controller.shortcutUp());
      case GlobalShortcutEventType.selectMode:
        if (event.mode != null) controller.selectMode(event.mode!);
      case GlobalShortcutEventType.suppressShortcut:
        controller.suppressShortcut();
      case GlobalShortcutEventType.cancel:
        unawaited(controller.reset());
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<VoiceSessionState>(voiceSessionProvider, (_, next) {
      final active = switch (next.phase) {
        VoiceSessionPhase.shortcutPreview ||
        VoiceSessionPhase.recording ||
        VoiceSessionPhase.processing => true,
        VoiceSessionPhase.idle ||
        VoiceSessionPhase.completed ||
        VoiceSessionPhase.failed => false,
      };
      unawaited(_bridge.setSessionActive(active));
    });
    ref.listen<AsyncValue<RuntimeSettings>>(runtimeSettingsProvider, (_, next) {
      final enabled = next.value?.waylandBackfill ?? false;
      unawaited(_bridge.setWaylandBackfill(enabled));
    });
    final enabled =
        (Platform.isMacOS || Platform.isWindows || Platform.isLinux) &&
        ref.watch(
          runtimeSettingsProvider.select(
            (value) => value.value?.globalShortcutEnabled ?? false,
          ),
        );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_setSubscribed(enabled));
    });
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): _cancelActiveSession,
      },
      child: Focus(autofocus: true, child: widget.child),
    );
  }
}
