import 'dart:io';

import 'package:flutter/services.dart';

class AndroidPlatformBridge {
  static const _channel = MethodChannel(
    'dev.raymond.voxwrite/android_platform',
  );

  Future<void> openFcitx5Download() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('openFcitx5Download');
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
