import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

class CapturedAudio {
  const CapturedAudio({
    required this.path,
    required this.mimeType,
    required this.duration,
  });

  final String path;
  final String mimeType;
  final Duration duration;
}

class AudioCaptureException implements Exception {
  const AudioCaptureException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract interface class AudioCapture {
  Stream<double> get amplitude;

  Future<void> start();

  Future<CapturedAudio> stop();

  Future<void> cancel();

  Future<void> dispose();
}

class FileAudioCapture implements AudioCapture {
  FileAudioCapture({
    AudioRecorder? recorder,
    bool verifyPermissionWithRecorder = true,
  }) : _recorder = recorder ?? AudioRecorder(),
       _ownsRecorder = recorder == null,
       _verifyPermissionWithRecorder = verifyPermissionWithRecorder;

  AudioRecorder _recorder;
  final bool _ownsRecorder;
  final bool _verifyPermissionWithRecorder;
  final StreamController<double> _amplitudeController =
      StreamController<double>.broadcast();
  StreamSubscription<Amplitude>? _amplitudeSubscription;
  String? _path;
  DateTime? _startedAt;

  @override
  Stream<double> get amplitude => _amplitudeController.stream;

  @override
  Future<void> start() async {
    if (await _recorder.isRecording()) {
      if (_path != null) return;
      await _renewOwnedRecorder();
    }
    if (_verifyPermissionWithRecorder && !await _recorder.hasPermission()) {
      throw const AudioCaptureException('没有麦克风权限，请在系统设置中允许 VoxWrite 使用麦克风。');
    }
    if (!await _recorder.isEncoderSupported(AudioEncoder.wav)) {
      throw const AudioCaptureException('当前设备不支持 WAV 录音。');
    }

    final temporaryDirectory = await getTemporaryDirectory();
    _path = '${temporaryDirectory.path}/voxwrite_${const Uuid().v4()}.wav';
    _startedAt = DateTime.now();
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
        autoGain: true,
        echoCancel: true,
        noiseSuppress: true,
      ),
      path: _path!,
    );

    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 100))
        .listen((value) => _amplitudeController.add(value.current));
  }

  @override
  Future<CapturedAudio> stop() async {
    if (!await _recorder.isRecording() || _path == null) {
      throw const AudioCaptureException('当前没有正在进行的录音。');
    }
    final stoppedPath = await _recorder.stop();
    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;
    final result = CapturedAudio(
      path: stoppedPath ?? _path!,
      mimeType: 'audio/wav',
      duration: DateTime.now().difference(_startedAt ?? DateTime.now()),
    );
    _path = null;
    _startedAt = null;
    return result;
  }

  @override
  Future<void> cancel() => _cancel(renewRecorder: true);

  Future<void> _cancel({required bool renewRecorder}) async {
    final cancelledPath = _path;
    if (await _recorder.isRecording()) await _recorder.cancel();
    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;
    _path = null;
    _startedAt = null;
    if (cancelledPath != null) {
      try {
        await File(cancelledPath).delete();
      } on FileSystemException {
        // The recorder may already have removed the temporary file.
      }
    }
    if (renewRecorder) await _renewOwnedRecorder();
  }

  Future<void> _renewOwnedRecorder() async {
    if (!_ownsRecorder) return;
    final staleRecorder = _recorder;
    _recorder = AudioRecorder();
    await staleRecorder.dispose();
  }

  @override
  Future<void> dispose() async {
    await _cancel(renewRecorder: false);
    await _amplitudeController.close();
    await _recorder.dispose();
  }
}
