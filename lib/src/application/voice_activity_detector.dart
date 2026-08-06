enum VoiceActivityDecision {
  none,
  speechStarted,
  trailingSilence,
  noSpeechTimeout,
  maximumDuration,
}

class VoiceActivityPolicy {
  const VoiceActivityPolicy({
    this.initialGrace = const Duration(milliseconds: 400),
    this.noSpeechTimeout = const Duration(seconds: 8),
    this.trailingSilence = const Duration(milliseconds: 1400),
    this.maximumDuration = const Duration(minutes: 2),
    this.speechThresholdDb = -40,
    this.continuingSpeechThresholdDb = -46,
    this.confirmationFrames = 2,
  });

  final Duration initialGrace;
  final Duration noSpeechTimeout;
  final Duration trailingSilence;
  final Duration maximumDuration;
  final double speechThresholdDb;
  final double continuingSpeechThresholdDb;
  final int confirmationFrames;
}

class VoiceActivityDetector {
  VoiceActivityDetector({this.policy = const VoiceActivityPolicy()});

  final VoiceActivityPolicy policy;
  bool _speechDetected = false;
  bool _finished = false;
  int _speechFrames = 0;
  Duration? _lastSpeechAt;

  bool get speechDetected => _speechDetected;

  VoiceActivityDecision add({
    required double amplitudeDb,
    required Duration elapsed,
  }) {
    if (_finished) return VoiceActivityDecision.none;
    if (elapsed >= policy.maximumDuration) {
      _finished = true;
      return VoiceActivityDecision.maximumDuration;
    }

    if (!_speechDetected) {
      if (elapsed >= policy.noSpeechTimeout) {
        _finished = true;
        return VoiceActivityDecision.noSpeechTimeout;
      }
      if (elapsed < policy.initialGrace) return VoiceActivityDecision.none;

      if (amplitudeDb >= policy.speechThresholdDb) {
        _speechFrames++;
      } else {
        _speechFrames = 0;
      }
      if (_speechFrames >= policy.confirmationFrames) {
        _speechDetected = true;
        _lastSpeechAt = elapsed;
        return VoiceActivityDecision.speechStarted;
      }
      return VoiceActivityDecision.none;
    }

    if (amplitudeDb >= policy.continuingSpeechThresholdDb) {
      _lastSpeechAt = elapsed;
      return VoiceActivityDecision.none;
    }

    final lastSpeechAt = _lastSpeechAt;
    if (lastSpeechAt != null &&
        elapsed - lastSpeechAt >= policy.trailingSilence) {
      _finished = true;
      return VoiceActivityDecision.trailingSilence;
    }
    return VoiceActivityDecision.none;
  }
}
