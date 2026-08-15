import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'src/application/android_voice_input_controller.dart';

/// Keeps the Linux process alive when the window's close button is pressed:
/// closing the window hides it to the system tray instead of quitting, so the
/// global F8 shortcuts keep working in the background (mirrors macOS).
/// Quit explicitly from the tray menu. The [AppLifecycleListener] stays alive
/// because [WidgetsBinding] holds a strong reference to its observers.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  _installLinuxCloseToTray();
  runApp(const ProviderScope(child: VoxWriteApp()));
}

void _installLinuxCloseToTray() {
  if (!Platform.isLinux) return;
  const lifecycle = MethodChannel('dev.raymond.voxwrite/lifecycle');
  AppLifecycleListener(
    onExitRequested: () async {
      // The window is closed by the user; veto the exit and hide the window
      // into the tray. The native side keeps the GTK window alive.
      try {
        await lifecycle.invokeMethod<void>('hideWindow');
      } on MissingPluginException {
        // The native bridge is unavailable (e.g. widget tests).
      }
      return AppExitResponse.cancel;
    },
  );
}

@pragma('vm:entry-point')
void voiceInputMain() {
  WidgetsFlutterBinding.ensureInitialized();
  AndroidVoiceInputController().initialize();
}
