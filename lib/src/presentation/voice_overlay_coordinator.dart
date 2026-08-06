import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/voice_session_controller.dart';
import '../domain/voice_mode.dart';
import '../domain/voice_session.dart';
import '../infrastructure/platform/platform_overlay_bridge.dart';

class VoiceOverlayCoordinator extends ConsumerStatefulWidget {
  const VoiceOverlayCoordinator({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<VoiceOverlayCoordinator> createState() =>
      _VoiceOverlayCoordinatorState();
}

class _VoiceOverlayCoordinatorState
    extends ConsumerState<VoiceOverlayCoordinator> {
  final PlatformOverlayBridge _overlay = PlatformOverlayBridge();
  Timer? _hideTimer;

  @override
  void dispose() {
    _hideTimer?.cancel();
    unawaited(_overlay.hide());
    super.dispose();
  }

  void _present(VoiceSessionState state) {
    _hideTimer?.cancel();
    switch (state.phase) {
      case VoiceSessionPhase.idle:
        unawaited(_overlay.hide());
      case VoiceSessionPhase.shortcutPreview:
        unawaited(
          _overlay.show(
            title: '选择模式 · ${state.mode.title}',
            detail: '松开 Fn 开始 · Shift 翻译 · Space 问与改写 · Esc 取消',
            kind: 'preview',
          ),
        );
      case VoiceSessionPhase.recording:
        unawaited(
          _overlay.show(
            title: '正在聆听 · ${state.mode.title}',
            detail: '再按一次 Fn 完成 · Esc 取消',
            kind: 'recording',
          ),
        );
      case VoiceSessionPhase.processing:
        unawaited(
          _overlay.show(
            title: 'Thinking',
            detail: '正在识别并整理文字 · Esc 取消',
            kind: 'processing',
          ),
        );
      case VoiceSessionPhase.completed:
        unawaited(
          _overlay.show(title: '已完成', detail: '结果已写入当前应用', kind: 'completed'),
        );
        _hideTimer = Timer(
          const Duration(milliseconds: 1400),
          () => unawaited(_overlay.hide()),
        );
      case VoiceSessionPhase.failed:
        unawaited(
          _overlay.show(
            title: '未完成',
            detail: state.failureMessage ?? '发生未知错误',
            kind: 'failed',
          ),
        );
        _hideTimer = Timer(
          const Duration(seconds: 4),
          () => unawaited(_overlay.hide()),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<VoiceSessionState>(voiceSessionProvider, (_, next) {
      _present(next);
    });
    return widget.child;
  }
}
