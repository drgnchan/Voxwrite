import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/history_entry.dart';
import '../infrastructure/providers/alibaba_qwen_tts_provider.dart';
import 'runtime_settings.dart';
import 'workflow_dependencies.dart';

enum HistorySpeechPhase { idle, loading, playing }

class HistorySpeechState {
  const HistorySpeechState({
    this.phase = HistorySpeechPhase.idle,
    this.entryId,
  });

  final HistorySpeechPhase phase;
  final String? entryId;
}

final historySpeechProvider =
    NotifierProvider<HistorySpeechController, HistorySpeechState>(
      HistorySpeechController.new,
    );

class HistorySpeechController extends Notifier<HistorySpeechState> {
  static const _cacheProfile = 'instruct-ethan-formal-v1';

  late final AudioPlayer _player;
  late final StreamSubscription<void> _completionSubscription;
  int _generation = 0;

  @override
  HistorySpeechState build() {
    _player = AudioPlayer();
    _completionSubscription = _player.onPlayerComplete.listen((_) {
      state = const HistorySpeechState();
    });
    ref.onDispose(() {
      _generation += 1;
      unawaited(_completionSubscription.cancel());
      unawaited(_player.dispose());
    });
    return const HistorySpeechState();
  }

  Future<void> toggle(HistoryEntry entry) async {
    final isActiveEntry =
        state.entryId == entry.id && state.phase != HistorySpeechPhase.idle;
    if (isActiveEntry) {
      await stop();
      return;
    }

    final generation = ++_generation;
    await _player.stop();
    if (generation != _generation) return;
    state = HistorySpeechState(
      phase: HistorySpeechPhase.loading,
      entryId: entry.id,
    );

    try {
      final audioFile = await _cachedAudioFile(entry);
      if (!await audioFile.exists()) {
        final apiKey = await ref.read(cloudApiKeyStoreProvider).read() ?? '';
        final settings = await ref.read(runtimeSettingsProvider.future);
        final audio = await AlibabaQwenTtsProvider(
          dio: ref.read(dioProvider),
          apiKey: apiKey,
          baseUrl: settings.speech.baseUrl,
        ).synthesize(entry.output);
        if (generation != _generation) return;

        final partialFile = File('${audioFile.path}.part');
        await partialFile.writeAsBytes(audio, flush: true);
        if (await audioFile.exists()) await audioFile.delete();
        await partialFile.rename(audioFile.path);
      }
      if (generation != _generation) return;

      await _player.play(DeviceFileSource(audioFile.path));
      if (generation != _generation) {
        await _player.stop();
        return;
      }
      state = HistorySpeechState(
        phase: HistorySpeechPhase.playing,
        entryId: entry.id,
      );
    } catch (_) {
      if (generation == _generation) state = const HistorySpeechState();
      rethrow;
    }
  }

  Future<void> stop() async {
    _generation += 1;
    await _player.stop();
    state = const HistorySpeechState();
  }

  Future<void> removeCachedAudio(String entryId) async {
    try {
      final cacheDirectory = await _cacheDirectory();
      if (!await cacheDirectory.exists()) return;
      await for (final entity in cacheDirectory.list()) {
        if (entity is! File) continue;
        final fileName = entity.uri.pathSegments.last;
        if (fileName == '$entryId.wav' || fileName.startsWith('$entryId-')) {
          await entity.delete();
        }
      }
    } on FileSystemException {
      // A cache cleanup failure must not prevent history deletion.
    }
  }

  Future<void> clearCachedAudio() async {
    try {
      final cacheDirectory = await _cacheDirectory();
      if (await cacheDirectory.exists()) {
        await cacheDirectory.delete(recursive: true);
      }
    } on FileSystemException {
      // The operating system may already have removed the temporary cache.
    }
  }

  Future<File> _cachedAudioFile(HistoryEntry entry) async {
    final cacheDirectory = await _cacheDirectory();
    await cacheDirectory.create(recursive: true);
    return File(
      '${cacheDirectory.path}${Platform.pathSeparator}'
      '${entry.id}-$_cacheProfile.wav',
    );
  }

  Future<Directory> _cacheDirectory() async {
    final temporaryDirectory = await getTemporaryDirectory();
    return Directory(
      '${temporaryDirectory.path}${Platform.pathSeparator}voxwrite_tts',
    );
  }
}
