import 'dart:io';

import 'package:flutter/services.dart';

class PlatformLifecycleBridge {
  static const _channel = MethodChannel('dev.raymond.voxwrite/lifecycle');

  Future<bool> isLaunchAtLoginSupported() async {
    if (!Platform.isMacOS) return false;
    try {
      return await _channel.invokeMethod<bool>('isLaunchAtLoginSupported') ??
          false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<bool> isLaunchAtLoginEnabled() async {
    if (!Platform.isMacOS) return false;
    try {
      return await _channel.invokeMethod<bool>('isLaunchAtLoginEnabled') ??
          false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<bool> setLaunchAtLogin(bool enabled) async {
    if (!Platform.isMacOS) return false;
    return await _channel.invokeMethod<bool>('setLaunchAtLogin', <String, bool>{
          'enabled': enabled,
        }) ??
        false;
  }
}
