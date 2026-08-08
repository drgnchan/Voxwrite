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

class AndroidImeController {
  static const _channel = MethodChannel('dev.raymond.voxwrite/android_ime');

  // The record plugin's permission helper requires an Activity and therefore
  // always reports false inside a headless InputMethodService engine. The
  // service performs the permission check with its native Context instead.
  final FileAudioCapture _capture = FileAudioCapture(
    verifyPermissionWithRecorder: false,
  );
  final Dio _dio = Dio();
  final CloudApiKeyStore _keyStore = CloudApiKeyStore(
    const FlutterSecureStorage(),
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
  String? _selectedText;
  Future<String>? _processing;

  void initialize() {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'start':
          final arguments = Map<Object?, Object?>.from(
            call.arguments as Map? ?? const <Object?, Object?>{},
          );
          await start(
            modeName: arguments['mode'] as String?,
            selectedText: arguments['selectedText'] as String?,
          );
          return true;
        case 'stop':
          return stop();
        case 'cancel':
          await cancel();
          return null;
        default:
          throw MissingPluginException('Unknown IME method ${call.method}');
      }
    });
  }

  Future<void> start({String? modeName, String? selectedText}) async {
    if (_recording || _processing != null) return;
    _mode =
        VoiceMode.values.where((value) => value.name == modeName).firstOrNull ??
        VoiceMode.dictation;
    _selectedText = selectedText;
    final hasMicrophonePermission =
        await _channel.invokeMethod<bool>('hasMicrophonePermission') ?? false;
    if (!hasMicrophonePermission) {
      throw const AudioCaptureException('没有麦克风权限，请在系统设置中允许 VoxWrite 使用麦克风。');
    }
    final runtime = await loadRuntimeSettings(SharedPreferencesAsync());
    await _capture.start();
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
        if (_recording && _detector?.speechDetected != true) {
          unawaited(_cancelWithoutSpeech());
        }
      });
    }
    _maximumRecordingTimer = Timer(const Duration(minutes: 2), () {
      if (_recording) unawaited(_finishAndCommit());
    });
    _progressTimer = Timer.periodic(
      const Duration(milliseconds: 120),
      (_) => unawaited(_sendProgress()),
    );
    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = _capture.amplitude.listen((amplitudeDb) {
      _latestAmplitudeDb = amplitudeDb;
      final detector = _detector;
      final startedAt = _startedAt;
      if (!_recording || detector == null || startedAt == null) return;
      final decision = detector.add(
        amplitudeDb: amplitudeDb,
        elapsed: DateTime.now().difference(startedAt),
      );
      switch (decision) {
        case VoiceActivityDecision.trailingSilence:
        case VoiceActivityDecision.maximumDuration:
          unawaited(_finishAndCommit());
        case VoiceActivityDecision.noSpeechTimeout:
          unawaited(_cancelWithoutSpeech());
        case VoiceActivityDecision.none:
        case VoiceActivityDecision.speechStarted:
          break;
      }
    });
  }

  Future<String?> stop() async {
    if (!_recording || _processing != null) return null;
    return _finish();
  }

  Future<void> cancel() async {
    _recording = false;
    await _stopMonitoring();
    await _capture.cancel();
    _selectedText = null;
    _mode = VoiceMode.dictation;
  }

  Future<void> _finishAndCommit() async {
    if (!_recording || _processing != null) return;
    try {
      await _channel.invokeMethod<void>('showProcessing');
      final output = await _finish();
      await _channel.invokeMethod<void>('commitText', <String, String>{
        'text': output,
      });
    } catch (error) {
      await _channel.invokeMethod<void>('showError', <String, String>{
        'message': error.toString().replaceFirst('Exception: ', ''),
      });
    }
  }

  Future<String> _finish() {
    final existing = _processing;
    if (existing != null) return existing;
    final operation = _processRecording();
    _processing = operation;
    return operation.whenComplete(() => _processing = null);
  }

  Future<String> _processRecording() async {
    _recording = false;
    await _stopMonitoring();
    String? audioPath;
    try {
      final captured = await _capture.stop();
      audioPath = captured.path;
      if (captured.duration < const Duration(milliseconds: 350)) {
        throw const CloudProviderException('录音太短，请重新说一次。');
      }

      final apiKey = await _keyStore.read().timeout(const Duration(seconds: 8));
      if (apiKey == null || apiKey.trim().isEmpty) {
        throw const CloudProviderException('请先打开 VoxWrite 保存阿里云 API Key。');
      }
      final preferences = SharedPreferencesAsync();
      final runtime = await loadRuntimeSettings(preferences);
      final cloud = runtime.cloud;
      if (cloud.vendor != CloudProviderVendor.alibaba) {
        throw CloudProviderException(
          '${cloud.vendor.label}语音识别适配器尚未启用，请暂时选择阿里云百炼。',
        );
      }
      final dictionary =
          await preferences.getStringList(personalDictionaryStorageKey) ??
          const <String>[];
      final recognizer = AlibabaQwenAsrProvider(
        dio: _dio,
        apiKey: apiKey,
        baseUrl: cloud.baseUrl.trim(),
        model: cloud.speechModel.trim().isEmpty
            ? cloud.vendor.defaultSpeechModel
            : cloud.speechModel.trim(),
      );
      final transcript = await recognizer.transcribe(
        audioPath: captured.path,
        vocabulary: dictionary,
        domainBackground: runtime.domainBackground,
      );
      final transformer = OpenAiCompatibleWritingProvider(
        dio: _dio,
        apiKey: apiKey,
        baseUrl: cloud.baseUrl.trim(),
        model: cloud.writingModel.trim().isEmpty
            ? cloud.vendor.defaultWritingModel
            : cloud.writingModel.trim(),
        enableThinking: cloud.vendor == CloudProviderVendor.alibaba
            ? false
            : null,
      );
      final output = await transformer.transform(
        WritingRequest(
          mode: _mode,
          transcript: transcript,
          selectedText: _selectedText,
          targetLanguages: _mode == VoiceMode.translation
              ? <String>[runtime.translationTarget]
              : const <String>[],
          personalDictionary: dictionary,
          domainBackground: runtime.domainBackground,
        ),
      );
      try {
        await HistoryStore(
          preferences: preferences,
        ).add(mode: _mode, transcript: transcript, output: output);
      } catch (_) {
        // History persistence must not block a successful text commit.
      }
      return output;
    } finally {
      _selectedText = null;
      _mode = VoiceMode.dictation;
      if (audioPath != null) {
        try {
          await File(audioPath).delete();
        } on FileSystemException {
          // Temporary audio cleanup is best effort.
        }
      }
    }
  }

  Future<void> _cancelWithoutSpeech() async {
    if (!_recording) return;
    await cancel();
    await _channel.invokeMethod<void>('showError', <String, String>{
      'message': '未检测到语音，请重试。',
    });
  }

  Future<void> _sendProgress() async {
    if (!_recording || _startedAt == null) return;
    try {
      await _channel.invokeMethod<void>('recordingProgress', <String, Object>{
        'elapsedMs': DateTime.now().difference(_startedAt!).inMilliseconds,
        'amplitudeDb': _latestAmplitudeDb,
      });
    } on PlatformException {
      // The input view may disappear while a progress frame is in flight.
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
