import 'dart:io';

import 'package:flutter/services.dart';

class PlatformOverlayBridge {
  static const _channel = MethodChannel('dev.raymond.voxwrite/overlay');

  Future<void> show({
    required String title,
    required String detail,
    required String kind,
  }) async {
    if (!Platform.isMacOS) return;
    try {
      await _channel.invokeMethod<void>('show', <String, String>{
        'title': title,
        'detail': detail,
        'kind': kind,
      });
    } on MissingPluginException {
      // Widget tests and non-native shells do not install the macOS bridge.
    }
  }

  Future<void> hide() async {
    if (!Platform.isMacOS) return;
    try {
      await _channel.invokeMethod<void>('hide');
    } on MissingPluginException {
      // Widget tests and non-native shells do not install the macOS bridge.
    }
  }
}
