import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/runtime_settings.dart';
import '../application/workflow_dependencies.dart';
import '../infrastructure/providers/alibaba_qwen_tts_provider.dart';

const _processTextChannel = MethodChannel('dev.raymond.voxwrite/process_text');

class AndroidProcessTextSpeechApp extends ConsumerStatefulWidget {
  const AndroidProcessTextSpeechApp({super.key});

  @override
  ConsumerState<AndroidProcessTextSpeechApp> createState() =>
      _AndroidProcessTextSpeechAppState();
}

class _AndroidProcessTextSpeechAppState
    extends ConsumerState<AndroidProcessTextSpeechApp> {
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<void>? _completionSubscription;
  String _status = '正在准备朗读…';
  String? _error;
  bool _playing = false;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _completionSubscription = _player.onPlayerComplete.listen((_) {
      unawaited(_close());
    });
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      final selectedText =
          await _processTextChannel.invokeMethod<String>('getSelectedText') ??
          '';
      if (selectedText.trim().isEmpty) {
        throw StateError('没有收到可朗读的文本。');
      }
      final apiKey = await ref.read(cloudApiKeyStoreProvider).read() ?? '';
      final settings = await ref.read(runtimeSettingsProvider.future);
      final audio = await AlibabaQwenTtsProvider(
        dio: ref.read(dioProvider),
        apiKey: apiKey,
        baseUrl: settings.speech.baseUrl,
      ).synthesize(selectedText);
      if (!mounted || _closing) return;

      await _player.play(BytesSource(audio, mimeType: 'audio/wav'));
      if (mounted) {
        setState(() {
          _playing = true;
          _status = '正在朗读所选文本';
        });
      }
    } catch (error) {
      if (mounted && !_closing) {
        setState(() => _error = error.toString());
      }
    }
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    await _player.stop();
    try {
      await _processTextChannel.invokeMethod<void>('close');
    } on MissingPluginException {
      // Only reachable outside the Android process-text activity.
    }
  }

  @override
  void dispose() {
    unawaited(_completionSubscription?.cancel());
    unawaited(_player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF6657E8);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      color: Colors.transparent,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seed),
        useMaterial3: true,
      ),
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Card(
                  elevation: 8,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
                    child: Row(
                      children: [
                        if (_error == null && !_playing)
                          const SizedBox.square(
                            dimension: 24,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          )
                        else
                          Icon(
                            _error == null
                                ? Icons.volume_up_rounded
                                : Icons.error_outline_rounded,
                            color: _error == null
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.error,
                          ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _error == null ? _status : '无法朗读',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              if (_error != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  _error!,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: _error == null ? '停止' : '关闭',
                          onPressed: _close,
                          icon: Icon(
                            _error == null
                                ? Icons.stop_circle_outlined
                                : Icons.close,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
