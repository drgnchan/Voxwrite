import 'package:flutter_test/flutter_test.dart';
import 'package:voxwrite/src/domain/voice_mode.dart';
import 'package:voxwrite/src/domain/voice_session.dart';

void main() {
  group('VoiceSessionMachine', () {
    test('selects a mode while Fn is held and starts on release', () {
      final machine = VoiceSessionMachine();

      expect(machine.shortcutDown().phase, VoiceSessionPhase.shortcutPreview);
      expect(
        machine.selectMode(VoiceMode.translation).mode,
        VoiceMode.translation,
      );

      final recording = machine.shortcutUp();
      expect(recording.phase, VoiceSessionPhase.recording);
      expect(recording.mode, VoiceMode.translation);
    });

    test('a second shortcut press stops the recording', () {
      final machine = VoiceSessionMachine()..start(VoiceMode.dictation);

      expect(machine.shortcutDown().phase, VoiceSessionPhase.processing);
    });

    test('reset cancels a recording without entering processing', () {
      final machine = VoiceSessionMachine()..start(VoiceMode.dictation);

      final cancelled = machine.reset();

      expect(cancelled.phase, VoiceSessionPhase.idle);
      expect(cancelled.transcript, isNull);
      expect(cancelled.output, isNull);
    });

    test('completes with transcript and polished output', () {
      final machine = VoiceSessionMachine()
        ..start(VoiceMode.dictation)
        ..stop();

      final completed = machine.complete(
        transcript: '嗯我们明天出发然后早点到',
        output: '我们明天出发，早点到。',
      );

      expect(completed.phase, VoiceSessionPhase.completed);
      expect(completed.output, '我们明天出发，早点到。');
    });
  });
}
