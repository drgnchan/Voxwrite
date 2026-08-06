import 'package:flutter_test/flutter_test.dart';
import 'package:voxwrite/src/application/voice_activity_detector.dart';

void main() {
  test('stops after confirmed speech followed by trailing silence', () {
    final detector = VoiceActivityDetector();

    expect(
      detector.add(
        amplitudeDb: -25,
        elapsed: const Duration(milliseconds: 500),
      ),
      VoiceActivityDecision.none,
    );
    expect(
      detector.add(
        amplitudeDb: -24,
        elapsed: const Duration(milliseconds: 600),
      ),
      VoiceActivityDecision.speechStarted,
    );
    expect(
      detector.add(
        amplitudeDb: -60,
        elapsed: const Duration(milliseconds: 1900),
      ),
      VoiceActivityDecision.none,
    );
    expect(
      detector.add(
        amplitudeDb: -60,
        elapsed: const Duration(milliseconds: 2000),
      ),
      VoiceActivityDecision.trailingSilence,
    );
  });

  test('rejects an accidental trigger when no speech arrives', () {
    final detector = VoiceActivityDetector();

    expect(
      detector.add(amplitudeDb: -80, elapsed: const Duration(seconds: 8)),
      VoiceActivityDecision.noSpeechTimeout,
    );
  });

  test('enforces maximum recording duration', () {
    final detector = VoiceActivityDetector();

    expect(
      detector.add(amplitudeDb: -20, elapsed: const Duration(minutes: 2)),
      VoiceActivityDecision.maximumDuration,
    );
  });
}
