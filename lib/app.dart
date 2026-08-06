import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/application/workflow_dependencies.dart';
import 'src/presentation/app_shell.dart';
import 'src/presentation/shortcut_coordinator.dart';
import 'src/presentation/voice_overlay_coordinator.dart';

class VoxWriteApp extends StatelessWidget {
  const VoxWriteApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF6657E8);
    return MaterialApp(
      title: 'VoxWrite',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF7F7FA),
        cardTheme: const CardThemeData(elevation: 0, margin: EdgeInsets.zero),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const _CloudApiKeyWarmup(
        child: ShortcutCoordinator(
          child: VoiceOverlayCoordinator(child: AppShell()),
        ),
      ),
    );
  }
}

class _CloudApiKeyWarmup extends ConsumerStatefulWidget {
  const _CloudApiKeyWarmup({required this.child});

  final Widget child;

  @override
  ConsumerState<_CloudApiKeyWarmup> createState() => _CloudApiKeyWarmupState();
}

class _CloudApiKeyWarmupState extends ConsumerState<_CloudApiKeyWarmup> {
  @override
  void initState() {
    super.initState();
    unawaited(_warmUp());
  }

  Future<void> _warmUp() async {
    try {
      await ref.read(cloudApiKeyStoreProvider).read();
    } catch (_) {
      // Settings and the voice workflow surface actionable storage errors.
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
