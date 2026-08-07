import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/voice_mode.dart';
import '../domain/voice_session.dart';
import '../domain/writing_request.dart';
import '../infrastructure/audio/file_audio_capture.dart';
import '../infrastructure/providers/alibaba_qwen_asr_provider.dart';
import '../infrastructure/providers/cloud_provider_settings.dart';
import '../infrastructure/providers/openai_compatible_writing_provider.dart';
import 'history_controller.dart';
import 'personal_dictionary.dart';
import 'runtime_settings.dart';
import 'voice_activity_detector.dart';
import 'workflow_dependencies.dart';

final voiceSessionProvider =
    NotifierProvider<VoiceSessionController, VoiceSessionState>(
      VoiceSessionController.new,
    );

class VoiceSessionController extends Notifier<VoiceSessionState> {
  late VoiceSessionMachine _machine;
  String? _selectedText;
  int _generation = 0;
  StreamSubscription<double>? _amplitudeSubscription;
  VoiceActivityDetector? _voiceActivityDetector;
  DateTime? _recordingStartedAt;
  Timer? _noSpeechTimer;
  Timer? _maximumRecordingTimer;
  bool _stopOnShortcutUp = false;
  Future<void>? _startOperation;

  @override
  VoiceSessionState build() {
    _machine = VoiceSessionMachine();
    ref.onDispose(() {
      _noSpeechTimer?.cancel();
      _maximumRecordingTimer?.cancel();
      unawaited(_amplitudeSubscription?.cancel());
    });
    return _machine.state;
  }

  Future<void> shortcutDown() async {
    if (_startOperation != null || state.phase == VoiceSessionPhase.recording) {
      _stopOnShortcutUp = true;
      return;
    }
    _stopOnShortcutUp = false;
    state = _machine.shortcutDown();
  }

  Future<void> shortcutUp() async {
    if (_stopOnShortcutUp) {
      _stopOnShortcutUp = false;
      await _startOperation;
      if (state.phase == VoiceSessionPhase.recording) {
        await stopAndProcess();
      }
      return;
    }
    if (_startOperation != null ||
        state.phase != VoiceSessionPhase.shortcutPreview) {
      return;
    }
    await start(state.mode);
  }

  void suppressShortcut() {
    _stopOnShortcutUp = false;
    if (state.phase == VoiceSessionPhase.shortcutPreview) {
      state = _machine.reset();
    }
  }

  void selectMode(VoiceMode mode) => state = _machine.selectMode(mode);

  Future<void> start(VoiceMode mode) {
    final existing = _startOperation;
    if (existing != null) return existing;
    late final Future<void> operation;
    operation = _start(mode).whenComplete(() {
      if (identical(_startOperation, operation)) _startOperation = null;
    });
    _startOperation = operation;
    return operation;
  }

  Future<void> _start(VoiceMode mode) async {
    if (state.isBusy) return;
    _stopOnShortcutUp = false;
    final generation = ++_generation;
    final destination = ref.read(textDestinationProvider);
    try {
      await destination.captureTarget();
      final selectedText = mode == VoiceMode.ask
          ? await destination.readSelection()
          : null;
      if (generation != _generation) return;
      _selectedText = selectedText;
      state = _machine.start(mode);
      final audioCapture = ref.read(audioCaptureProvider);
      await audioCapture.start();
      if (generation != _generation) {
        await audioCapture.cancel();
      } else {
        await _beginVoiceActivityMonitoring(audioCapture, generation);
      }
    } catch (error) {
      if (generation == _generation) {
        await _stopVoiceActivityMonitoring();
        await destination.clearTarget();
        state = _machine.fail(_errorMessage(error));
      }
    }
  }

  Future<void> stopAndProcess() async {
    await _startOperation;
    if (state.phase != VoiceSessionPhase.recording) return;
    _stopOnShortcutUp = false;
    await _stopVoiceActivityMonitoring();
    state = _machine.stop();
    final generation = ++_generation;
    final mode = state.mode;
    final selectedText = _selectedText;

    String? audioPath;
    try {
      final captured = await ref.read(audioCaptureProvider).stop();
      audioPath = captured.path;
      if (captured.duration < const Duration(milliseconds: 350)) {
        throw const CloudProviderException('录音太短，请重新说一次。');
      }

      final runtime = ref.read(runtimeSettingsProvider);
      final cloud = runtime.cloud;
      final personalDictionary = await ref.read(
        personalDictionaryProvider.future,
      );
      if (generation != _generation) return;
      if (cloud.vendor != CloudProviderVendor.alibaba) {
        throw CloudProviderException(
          '${cloud.vendor.label}语音识别适配器尚未启用，请暂时选择阿里云百炼。',
        );
      }

      final apiKey = await ref
          .read(cloudApiKeyStoreProvider)
          .read()
          .timeout(const Duration(seconds: 8));
      if (apiKey == null || apiKey.trim().isEmpty) {
        throw const CloudProviderException('请先在设置中安全保存阿里云百炼 API Key。');
      }

      final dio = ref.read(dioProvider);
      final recognizer = AlibabaQwenAsrProvider(
        dio: dio,
        apiKey: apiKey,
        baseUrl: cloud.baseUrl,
        model: cloud.speechModel.trim().isEmpty
            ? cloud.vendor.defaultSpeechModel
            : cloud.speechModel.trim(),
      );
      final transcript = await recognizer.transcribe(
        audioPath: audioPath,
        vocabulary: personalDictionary,
      );
      if (generation != _generation) return;

      final transformer = OpenAiCompatibleWritingProvider(
        dio: dio,
        apiKey: apiKey,
        baseUrl: cloud.baseUrl,
        model: cloud.writingModel,
        enableThinking: cloud.vendor == CloudProviderVendor.alibaba
            ? false
            : null,
      );
      final output = await transformer.transform(
        WritingRequest(
          mode: mode,
          transcript: transcript,
          selectedText: selectedText,
          targetLanguages: mode == VoiceMode.translation
              ? <String>[runtime.translationTarget]
              : const <String>[],
          personalDictionary: personalDictionary,
        ),
      );
      if (generation != _generation) return;

      await ref.read(textDestinationProvider).insert(output);
      if (generation == _generation) {
        try {
          await ref
              .read(historyProvider.notifier)
              .add(mode: mode, transcript: transcript, output: output);
        } catch (_) {
          // Local history failure must not turn a successful dictation into an error.
        }
        state = _machine.complete(transcript: transcript, output: output);
      }
    } catch (error) {
      if (generation == _generation) {
        state = _machine.fail(_errorMessage(error));
      }
    } finally {
      if (generation == _generation) {
        _selectedText = null;
        await ref.read(textDestinationProvider).clearTarget();
      }
      if (audioPath != null) {
        try {
          await File(audioPath).delete();
        } on FileSystemException {
          // Temporary audio is best-effort cleanup and is never added to history.
        }
      }
    }
  }

  Future<void> reset() async {
    _generation++;
    _stopOnShortcutUp = false;
    await _stopVoiceActivityMonitoring();
    if (state.phase == VoiceSessionPhase.recording) {
      await ref.read(audioCaptureProvider).cancel();
    }
    _selectedText = null;
    await ref.read(textDestinationProvider).clearTarget();
    state = _machine.reset();
  }

  Future<void> _beginVoiceActivityMonitoring(
    AudioCapture capture,
    int generation,
  ) async {
    await _stopVoiceActivityMonitoring();
    final autoStopOnSilence = ref
        .read(runtimeSettingsProvider)
        .autoStopOnSilence;
    _voiceActivityDetector = VoiceActivityDetector(
      policy: autoStopOnSilence
          ? const VoiceActivityPolicy()
          : const VoiceActivityPolicy(
              noSpeechTimeout: Duration(minutes: 2),
              trailingSilence: Duration(minutes: 2),
            ),
    );
    _recordingStartedAt = DateTime.now();
    _maximumRecordingTimer = Timer(const Duration(minutes: 2), () {
      if (generation == _generation &&
          state.phase == VoiceSessionPhase.recording) {
        unawaited(stopAndProcess());
      }
    });
    if (autoStopOnSilence) {
      _noSpeechTimer = Timer(const Duration(seconds: 8), () {
        if (generation == _generation &&
            state.phase == VoiceSessionPhase.recording &&
            _voiceActivityDetector?.speechDetected != true) {
          unawaited(_failRecordingWithoutSpeech(generation));
        }
      });
    }
    _amplitudeSubscription = capture.amplitude.listen((amplitudeDb) {
      if (generation != _generation ||
          state.phase != VoiceSessionPhase.recording) {
        return;
      }
      final detector = _voiceActivityDetector;
      final startedAt = _recordingStartedAt;
      if (detector == null || startedAt == null) return;
      final decision = detector.add(
        amplitudeDb: amplitudeDb,
        elapsed: DateTime.now().difference(startedAt),
      );
      switch (decision) {
        case VoiceActivityDecision.trailingSilence:
        case VoiceActivityDecision.maximumDuration:
          unawaited(stopAndProcess());
        case VoiceActivityDecision.noSpeechTimeout:
          unawaited(_failRecordingWithoutSpeech(generation));
        case VoiceActivityDecision.none:
        case VoiceActivityDecision.speechStarted:
          break;
      }
    });
  }

  Future<void> _stopVoiceActivityMonitoring() async {
    _noSpeechTimer?.cancel();
    _noSpeechTimer = null;
    _maximumRecordingTimer?.cancel();
    _maximumRecordingTimer = null;
    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;
    _voiceActivityDetector = null;
    _recordingStartedAt = null;
  }

  Future<void> _failRecordingWithoutSpeech(int generation) async {
    if (generation != _generation ||
        state.phase != VoiceSessionPhase.recording) {
      return;
    }
    _generation++;
    _stopOnShortcutUp = false;
    await _stopVoiceActivityMonitoring();
    await ref.read(audioCaptureProvider).cancel();
    _selectedText = null;
    await ref.read(textDestinationProvider).clearTarget();
    state = _machine.fail('未检测到语音，请靠近麦克风后重试。');
  }

  String _errorMessage(Object error) {
    if (error is TimeoutException) {
      return '读取系统安全存储超时，请在 Keychain 确认窗口中选择“始终允许”。';
    }
    if (error is CloudProviderException) return error.message;
    return error.toString().replaceFirst('Exception: ', '');
  }
}
