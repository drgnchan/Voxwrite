import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'src/application/android_voice_input_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: VoxWriteApp()));
}

@pragma('vm:entry-point')
void voiceInputMain() {
  WidgetsFlutterBinding.ensureInitialized();
  AndroidVoiceInputController().initialize();
}
