import 'dart:io';

import 'package:flutter/services.dart';

import '../../domain/writing_request.dart';

class PlatformTextDestination implements TextDestination {
  static const _channel = MethodChannel(
    'dev.raymond.voxwrite/text_destination',
  );

  @override
  Future<void> captureTarget() async {
    if (!Platform.isMacOS && !Platform.isWindows) return;
    await _channel.invokeMethod<bool>('captureTarget');
  }

  @override
  Future<String?> readSelection() async {
    if (!Platform.isMacOS && !Platform.isWindows) return null;
    return _channel.invokeMethod<String>('readSelection');
  }

  @override
  Future<void> insert(String text) async {
    if (Platform.isMacOS || Platform.isWindows) {
      final inserted = await _channel.invokeMethod<bool>(
        'insertText',
        <String, String>{'text': text},
      );
      if (inserted == true) return;
    }

    await Clipboard.setData(ClipboardData(text: text));
  }

  @override
  Future<void> clearTarget() async {
    if (!Platform.isMacOS && !Platform.isWindows) return;
    await _channel.invokeMethod<void>('clearTarget');
  }
}
