import 'voice_mode.dart';

enum VoiceSessionPhase {
  idle,
  shortcutPreview,
  recording,
  processing,
  completed,
  failed,
}

class VoiceSessionState {
  const VoiceSessionState({
    this.phase = VoiceSessionPhase.idle,
    this.mode = VoiceMode.dictation,
    this.transcript,
    this.output,
    this.failureMessage,
  });

  final VoiceSessionPhase phase;
  final VoiceMode mode;
  final String? transcript;
  final String? output;
  final String? failureMessage;

  bool get isBusy =>
      phase == VoiceSessionPhase.recording ||
      phase == VoiceSessionPhase.processing;

  VoiceSessionState copyWith({
    VoiceSessionPhase? phase,
    VoiceMode? mode,
    String? transcript,
    String? output,
    String? failureMessage,
    bool clearTransient = false,
  }) {
    return VoiceSessionState(
      phase: phase ?? this.phase,
      mode: mode ?? this.mode,
      transcript: clearTransient ? null : transcript ?? this.transcript,
      output: clearTransient ? null : output ?? this.output,
      failureMessage: clearTransient
          ? null
          : failureMessage ?? this.failureMessage,
    );
  }
}

class VoiceSessionMachine {
  VoiceSessionState _state = const VoiceSessionState();

  VoiceSessionState get state => _state;

  VoiceSessionState shortcutDown() {
    switch (_state.phase) {
      case VoiceSessionPhase.idle:
      case VoiceSessionPhase.completed:
      case VoiceSessionPhase.failed:
        _state = const VoiceSessionState(
          phase: VoiceSessionPhase.shortcutPreview,
        );
      case VoiceSessionPhase.recording:
        _state = _state.copyWith(phase: VoiceSessionPhase.processing);
      case VoiceSessionPhase.shortcutPreview:
      case VoiceSessionPhase.processing:
        break;
    }
    return _state;
  }

  VoiceSessionState selectMode(VoiceMode mode) {
    if (_state.phase == VoiceSessionPhase.shortcutPreview) {
      _state = _state.copyWith(mode: mode);
    }
    return _state;
  }

  VoiceSessionState shortcutUp() {
    if (_state.phase == VoiceSessionPhase.shortcutPreview) {
      _state = _state.copyWith(phase: VoiceSessionPhase.recording);
    }
    return _state;
  }

  VoiceSessionState start(VoiceMode mode) {
    _state = VoiceSessionState(phase: VoiceSessionPhase.recording, mode: mode);
    return _state;
  }

  VoiceSessionState stop() {
    if (_state.phase == VoiceSessionPhase.recording) {
      _state = _state.copyWith(phase: VoiceSessionPhase.processing);
    }
    return _state;
  }

  VoiceSessionState complete({
    required String transcript,
    required String output,
  }) {
    _state = _state.copyWith(
      phase: VoiceSessionPhase.completed,
      transcript: transcript,
      output: output,
    );
    return _state;
  }

  VoiceSessionState fail(String message) {
    _state = _state.copyWith(
      phase: VoiceSessionPhase.failed,
      failureMessage: message,
    );
    return _state;
  }

  VoiceSessionState reset() {
    _state = const VoiceSessionState();
    return _state;
  }
}
