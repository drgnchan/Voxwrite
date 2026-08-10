import 'dart:io';

import 'package:flutter/services.dart';

class AndroidPlatformBridge {
  static const _channel = MethodChannel(
    'dev.raymond.voxwrite/android_platform',
  );

  Future<void> openTrimeSettings() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('openTrimeSettings');
  }

  Future<void> openInputMethodSettings() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('openInputMethodSettings');
  }

  Future<void> showInputMethodPicker() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('showInputMethodPicker');
  }
}
