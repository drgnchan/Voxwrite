import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/voice_mode.dart';
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

class AndroidVoiceInputController {
  static const _channel = MethodChannel(
    'dev.raymond.voxwrite/android_voice_input',
  );

  // The record plugin's permission helper requires an Activity and therefore
  // reports false inside a headless InputMethodService engine. The native
  // auxiliary voice IME performs the permission check with its own Context.
  final FileAudioCapture _capture = FileAudioCapture(
    verifyPermissionWithRecorder: false,
  );
  final Dio _dio = Dio();
  final CloudApiKeyStore _keyStore = CloudApiKeyStore(
    const FlutterSecureStorage(),
  );
  final CloudApiKeyStore _writingKeyStore = CloudApiKeyStore(
    const FlutterSecureStorage(),
    storageKey: writingApiKeyStorageKey,
  );
  StreamSubscription<double>? _amplitudeSubscription;
  VoiceActivityDetector? _detector;
  DateTime? _startedAt;
  Timer? _noSpeechTimer;
  Timer? _maximumRecordingTimer;
  Timer? _progressTimer;
  double _latestAmplitudeDb = -80;
  bool _recording = false;
  VoiceMode _mode = VoiceMode.dictation;
  Future<String?>? _processing;
  int _generation = 0;

  void initialize() {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'start':
          final arguments = Map<Object?, Object?>.from(
            call.arguments as Map? ?? const <Object?, Object?>{},
          );
          await start(modeName: arguments['mode'] as String?);
          return true;
        case 'setMode':
          final arguments = Map<Object?, Object?>.from(
            call.arguments as Map? ?? const <Object?, Object?>{},
          );
          setMode(arguments['mode'] as String?);
          return null;
        case 'stop':
          return stop();
        case 'cancel':
          await cancel();
          return null;
        default:
          throw MissingPluginException(
            'Unknown voice input method ${call.method}',
          );
      }
    });
  }

  Future<void> start({String? modeName}) async {
    if (_recording || _processing != null) return;
    final generation = ++_generation;
    setMode(modeName);
    final hasMicrophonePermission =
        await _channel.invokeMethod<bool>('hasMicrophonePermission') ?? false;
    if (!hasMicrophonePermission) {
      throw const AudioCaptureException('没有麦克风权限，请在系统设置中允许 VoxWrite 使用麦克风。');
    }
    final runtime = await loadRuntimeSettings(SharedPreferencesAsync());
    if (generation != _generation) return;
    await _capture.start();
    if (generation != _generation) {
      await _capture.cancel();
      return;
    }
    _recording = true;
    _latestAmplitudeDb = -80;
    _detector = VoiceActivityDetector(
      policy: runtime.autoStopOnSilence
          ? const VoiceActivityPolicy()
          : const VoiceActivityPolicy(
              noSpeechTimeout: Duration(minutes: 2),
              trailingSilence: Duration(minutes: 2),
            ),
    );
    _startedAt = DateTime.now();
    if (runtime.autoStopOnSilence) {
      _noSpeechTimer = Timer(const Duration(seconds: 8), () {
        if (_recording &&
            generation == _generation &&
            _detector?.speechDetected != true) {
          unawaited(_cancelWithoutSpeech(generation));
        }
      });
    }
    _maximumRecordingTimer = Timer(const Duration(minutes: 2), () {
      if (_recording && generation == _generation) {
        unawaited(_finishAndCommit(generation));
      }
    });
    _progressTimer = Timer.periodic(
      const Duration(milliseconds: 120),
      (_) => unawaited(_sendProgress(generation)),
    );
    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = _capture.amplitude.listen((amplitudeDb) {
      _latestAmplitudeDb = amplitudeDb;
      final detector = _detector;
      final startedAt = _startedAt;
      if (!_recording ||
          generation != _generation ||
          detector == null ||
          startedAt == null) {
        return;
      }
      final decision = detector.add(
        amplitudeDb: amplitudeDb,
        elapsed: DateTime.now().difference(startedAt),
      );
      switch (decision) {
        case VoiceActivityDecision.trailingSilence:
        case VoiceActivityDecision.maximumDuration:
          unawaited(_finishAndCommit(generation));
        case VoiceActivityDecision.noSpeechTimeout:
          unawaited(_cancelWithoutSpeech(generation));
        case VoiceActivityDecision.none:
        case VoiceActivityDecision.speechStarted:
          break;
      }
    });
  }

  void setMode(String? modeName) {
    if (_processing != null) return;
    _mode = modeName == VoiceMode.translation.name
        ? VoiceMode.translation
        : VoiceMode.dictation;
  }

  Future<String?> stop() async {
    if (!_recording || _processing != null) return null;
    return _finish(_generation);
  }

  Future<void> cancel() async {
    _generation++;
    _recording = false;
    _processing = null;
    _mode = VoiceMode.dictation;
    await _stopMonitoring();
    await _capture.cancel();
  }

  Future<void> _finishAndCommit(int generation) async {
    if (!_recording || _processing != null || generation != _generation) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('showProcessing');
      final output = await _finish(generation);
      if (generation != _generation || output == null || output.isEmpty) return;
      await _channel.invokeMethod<void>('commitText', <String, String>{
        'text': output,
      });
    } catch (error) {
      if (generation != _generation) return;
      await _channel.invokeMethod<void>('showError', <String, String>{
        'message': error.toString().replaceFirst('Exception: ', ''),
      });
    }
  }

  Future<String?> _finish(int generation) {
    final existing = _processing;
    if (existing != null) return existing;
    late final Future<String?> operation;
    operation = _processRecording(generation).whenComplete(() {
      if (identical(_processing, operation)) _processing = null;
    });
    _processing = operation;
    return operation;
  }

  Future<String?> _processRecording(int generation) async {
    _recording = false;
    await _stopMonitoring();
    String? audioPath;
    try {
      final captured = await _capture.stop();
      audioPath = captured.path;
      if (generation != _generation) return null;
      if (captured.duration < const Duration(milliseconds: 350)) {
        throw const CloudProviderException('录音太短，请重新说一次。');
      }

      final speechApiKey = await _keyStore.read().timeout(
        const Duration(seconds: 8),
      );
      if (generation != _generation) return null;
      if (speechApiKey == null || speechApiKey.trim().isEmpty) {
        throw const CloudProviderException('请先打开 VoxWrite 保存阿里云 API Key。');
      }
      final writingApiKey = await _writingKeyStore.read().timeout(
        const Duration(seconds: 8),
      );
      if (generation != _generation) return null;
      if (writingApiKey == null || writingApiKey.trim().isEmpty) {
        throw const CloudProviderException('请先打开 VoxWrite 保存文本模型 API Key。');
      }
      final preferences = SharedPreferencesAsync();
      final runtime = await loadRuntimeSettings(preferences);
      if (generation != _generation) return null;
      final writing = runtime.writing;
      final speech = runtime.speech;
      final dictionary =
          await preferences.getStringList(personalDictionaryStorageKey) ??
          const <String>[];
      if (generation != _generation) return null;
      const speechDefaults = SpeechProviderSettings();
      final recognizer = AlibabaQwenAsrProvider(
        dio: _dio,
        apiKey: speechApiKey,
        baseUrl: speech.baseUrl.trim().isEmpty
            ? speechDefaults.baseUrl
            : speech.baseUrl.trim(),
        model: speech.model.trim().isEmpty
            ? speechDefaults.model
            : speech.model.trim(),
      );
      final transcript = await recognizer.transcribe(
        audioPath: captured.path,
        vocabulary: dictionary,
        domainBackground: runtime.domainBackground,
      );
      if (generation != _generation) return null;
      final transformer = OpenAiCompatibleWritingProvider(
        dio: _dio,
        apiKey: writingApiKey,
        baseUrl: writing.baseUrl.trim(),
        model: writing.model.trim().isEmpty
            ? writing.vendor.defaultWritingModel
            : writing.model.trim(),
        extraBody: writing.vendor.disableThinkingFields,
      );
      final output = await transformer.transform(
        WritingRequest(
          mode: _mode,
          transcript: transcript,
          targetLanguages: _mode == VoiceMode.translation
              ? <String>[runtime.translationTarget]
              : const <String>[],
          personalDictionary: dictionary,
          domainBackground: runtime.domainBackground,
        ),
      );
      if (generation != _generation) return null;
      try {
        await HistoryStore(
          preferences: preferences,
        ).add(mode: _mode, transcript: transcript, output: output);
      } catch (_) {
        // History persistence must not block a successful text commit.
      }
      return output;
    } finally {
      if (audioPath != null) {
        try {
          await File(audioPath).delete();
        } on FileSystemException {
          // Temporary audio cleanup is best effort.
        }
      }
    }
  }

  Future<void> _cancelWithoutSpeech(int generation) async {
    if (!_recording || generation != _generation) return;
    await cancel();
    await _channel.invokeMethod<void>('showError', <String, String>{
      'message': '未检测到语音，请重试。',
    });
  }

  Future<void> _sendProgress(int generation) async {
    if (!_recording || generation != _generation || _startedAt == null) return;
    try {
      await _channel.invokeMethod<void>('recordingProgress', <String, Object>{
        'elapsedMs': DateTime.now().difference(_startedAt!).inMilliseconds,
        'amplitudeDb': _latestAmplitudeDb,
      });
    } on PlatformException {
      // The voice input view may disappear while a progress frame is in flight.
    }
  }

  Future<void> _stopMonitoring() async {
    _progressTimer?.cancel();
    _progressTimer = null;
    _noSpeechTimer?.cancel();
    _noSpeechTimer = null;
    _maximumRecordingTimer?.cancel();
    _maximumRecordingTimer = null;
    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;
    _detector = null;
    _startedAt = null;
    _latestAmplitudeDb = -80;
  }
}
