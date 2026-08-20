import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voxwrite/app.dart';
import 'package:voxwrite/src/application/voice_session_controller.dart';
import 'package:voxwrite/src/domain/voice_session.dart';
import 'package:voxwrite/src/presentation/pages/home_page.dart';

void main() {
  testWidgets('renders the three core voice modes', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const ProviderScope(child: VoxWriteApp()));
    await tester.pumpAndSettle();

    expect(find.text('开口起草，让文字自然成形'), findsOneWidget);
    expect(find.text('口述'), findsOneWidget);
    expect(find.text('翻译'), findsOneWidget);
    expect(find.text('问与改写'), findsOneWidget);
  });

  testWidgets('Escape cancels a recording while the window is focused', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        voiceSessionProvider.overrideWith(_RecordingVoiceSessionController.new),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const VoxWriteApp(),
      ),
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    final controller =
        container.read(voiceSessionProvider.notifier)
            as _RecordingVoiceSessionController;
    expect(controller.resetCalled, isTrue);
    expect(container.read(voiceSessionProvider).phase, VoiceSessionPhase.idle);
  });

  testWidgets('recording panel can discard a recording', (tester) async {
    final container = ProviderContainer(
      overrides: [
        voiceSessionProvider.overrideWith(_RecordingVoiceSessionController.new),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: HomePage())),
      ),
    );

    expect(find.text('停止'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);

    await tester.ensureVisible(find.text('取消'));
    await tester.tap(find.text('取消'));
    await tester.pump();

    final controller =
        container.read(voiceSessionProvider.notifier)
            as _RecordingVoiceSessionController;
    expect(controller.resetCalled, isTrue);
    expect(container.read(voiceSessionProvider).phase, VoiceSessionPhase.idle);
  });
}

class _RecordingVoiceSessionController extends VoiceSessionController {
  bool resetCalled = false;

  @override
  VoiceSessionState build() =>
      const VoiceSessionState(phase: VoiceSessionPhase.recording);

  @override
  Future<void> reset() async {
    resetCalled = true;
    state = const VoiceSessionState();
  }
}
