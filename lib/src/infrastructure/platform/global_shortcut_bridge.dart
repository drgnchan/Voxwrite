import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../../domain/voice_mode.dart';

enum GlobalShortcutEventType {
  functionDown,
  functionUp,
  selectMode,
  suppressShortcut,
  cancel,
}

class GlobalShortcutEvent {
  const GlobalShortcutEvent(this.type, {this.mode});

  final GlobalShortcutEventType type;
  final VoiceMode? mode;

  static GlobalShortcutEvent fromMap(Map<Object?, Object?> map) {
    final type = map['type'];
    return switch (type) {
      'fnDown' => const GlobalShortcutEvent(
        GlobalShortcutEventType.functionDown,
      ),
      'fnUp' => const GlobalShortcutEvent(GlobalShortcutEventType.functionUp),
      'selectTranslation' => const GlobalShortcutEvent(
        GlobalShortcutEventType.selectMode,
        mode: VoiceMode.translation,
      ),
      'selectAsk' => const GlobalShortcutEvent(
        GlobalShortcutEventType.selectMode,
        mode: VoiceMode.ask,
      ),
      'suppressShortcut' => const GlobalShortcutEvent(
        GlobalShortcutEventType.suppressShortcut,
      ),
      'cancel' => const GlobalShortcutEvent(GlobalShortcutEventType.cancel),
      _ => throw FormatException('Unknown shortcut event: $type'),
    };
  }
}

class GlobalShortcutBridge {
  static const _events = EventChannel('dev.raymond.voxwrite/shortcuts');
  static const _methods = MethodChannel('dev.raymond.voxwrite/permissions');

  Stream<GlobalShortcutEvent> events() {
    if (!Platform.isMacOS && !Platform.isWindows) {
      return const Stream.empty();
    }
    return _events.receiveBroadcastStream().map((dynamic event) {
      return GlobalShortcutEvent.fromMap(
        Map<Object?, Object?>.from(event as Map),
      );
    });
  }

  Future<bool> hasAccessibilityPermission() async {
    if (!Platform.isMacOS) return true;
    try {
      return await _methods.invokeMethod<bool>('hasAccessibilityPermission') ??
          false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<bool> requestAccessibilityPermission() async {
    if (!Platform.isMacOS) return true;
    try {
      return await _methods.invokeMethod<bool>(
            'requestAccessibilityPermission',
          ) ??
          false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<bool> hasInputMonitoringPermission() async {
    if (!Platform.isMacOS) return true;
    try {
      return await _methods.invokeMethod<bool>(
            'hasInputMonitoringPermission',
          ) ??
          false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<bool> requestInputMonitoringPermission() async {
    if (!Platform.isMacOS) return true;
    try {
      return await _methods.invokeMethod<bool>(
            'requestInputMonitoringPermission',
          ) ??
          false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<void> setSessionActive(bool active) async {
    if (!Platform.isMacOS) return;
    try {
      await _methods.invokeMethod<void>('setShortcutSessionActive', {
        'active': active,
      });
    } on MissingPluginException {
      // Widget tests do not install the macOS bridge.
    }
  }

  Future<void> openAccessibilitySettings() async {
    if (!Platform.isMacOS) return;
    try {
      await _methods.invokeMethod<void>('openAccessibilitySettings');
    } on MissingPluginException {
      // Widget tests do not install the macOS bridge.
    }
  }

  Future<void> openInputMonitoringSettings() async {
    if (!Platform.isMacOS) return;
    try {
      await _methods.invokeMethod<void>('openInputMonitoringSettings');
    } on MissingPluginException {
      // Widget tests do not install the macOS bridge.
    }
  }
}
