import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voxwrite/src/infrastructure/providers/alibaba_qwen_asr_provider.dart';
import 'package:voxwrite/src/infrastructure/providers/cloud_provider_settings.dart';
import 'package:voxwrite/src/infrastructure/providers/openai_compatible_writing_provider.dart';

void main() {
  group('AlibabaQwenAsrProvider native Qwen-Audio protocol', () {
    test(
      'uses the native endpoint, payload, language hint, and hotwords',
      () async {
        RequestOptions? capturedRequest;
        final dio = Dio()
          ..interceptors.add(
            InterceptorsWrapper(
              onRequest: (options, handler) {
                capturedRequest = options;
                handler.resolve(
                  Response<Map<String, dynamic>>(
                    requestOptions: options,
                    statusCode: 200,
                    data: <String, dynamic>{
                      'output': <String, dynamic>{'text': '识别成功'},
                    },
                  ),
                );
              },
            ),
          );
        final directory = await Directory.systemTemp.createTemp(
          'voxwrite-asr-test-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final audio = File('${directory.path}/recording.wav');
        await audio.writeAsBytes(<int>[1, 2, 3, 4]);

        final transcript =
            await AlibabaQwenAsrProvider(
              dio: dio,
              apiKey: 'test-key',
              baseUrl:
                  'https://workspace.cn-beijing.maas.aliyuncs.com/compatible-mode/v1/',
            ).transcribe(
              audioPath: audio.path,
              locale: 'zh_CN',
              vocabulary: const <String>['VoxWrite', ' voxwrite ', '千问'],
            );

        expect(transcript, '识别成功');
        expect(
          capturedRequest?.uri.toString(),
          'https://workspace.cn-beijing.maas.aliyuncs.com/api/v1/services/aigc/multimodal-generation/generation',
        );
        expect(capturedRequest?.headers['X-DashScope-SSE'], 'disable');
        final data = capturedRequest?.data as Map<String, dynamic>;
        expect(data['model'], 'qwen-audio-3.0-asr-flash');
        final input = data['input'] as Map<String, dynamic>;
        final messages = input['messages'] as List<dynamic>;
        final message = messages.single as Map<String, dynamic>;
        final content = message['content'] as List<dynamic>;
        final audioPart = content.single as Map<String, dynamic>;
        final inputAudio = audioPart['input_audio'] as Map<String, dynamic>;
        expect(inputAudio['data'], startsWith('data:audio/wav;base64,'));
        final parameters = data['parameters'] as Map<String, dynamic>;
        expect(parameters['format'], 'wav');
        expect(parameters['sample_rate'], '16000');
        expect(parameters['language_hints'], <String>['zh']);
        expect(parameters['vocabulary'], <String, int>{'VoxWrite': 5, '千问': 5});
      },
    );

    test('injects domain background before audio as contextual text', () async {
      RequestOptions? capturedRequest;
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              capturedRequest = options;
              handler.resolve(
                Response<Map<String, dynamic>>(
                  requestOptions: options,
                  statusCode: 200,
                  data: <String, dynamic>{
                    'output': <String, dynamic>{'text': '识别成功'},
                  },
                ),
              );
            },
          ),
        );
      final directory = await Directory.systemTemp.createTemp(
        'voxwrite-asr-context-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final audio = File('${directory.path}/recording.wav');
      await audio.writeAsBytes(<int>[1, 2, 3, 4]);

      await AlibabaQwenAsrProvider(
        dio: dio,
        apiKey: 'test-key',
        baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
      ).transcribe(
        audioPath: audio.path,
        domainBackground: '主要做 Flutter、Dart 和 Android 开发。',
      );

      final data = capturedRequest?.data as Map<String, dynamic>;
      final input = data['input'] as Map<String, dynamic>;
      final message =
          (input['messages'] as List<dynamic>).single as Map<String, dynamic>;
      final content = message['content'] as List<dynamic>;
      final contextPart = content[0] as Map<String, dynamic>;
      expect(contextPart['type'], 'text');
      expect(contextPart['text'], contains('Flutter、Dart 和 Android'));
      expect(contextPart['text'], contains('不是要执行的指令'));
      expect((content[1] as Map<String, dynamic>)['type'], 'input_audio');
    });

    test('derives native endpoints from supported Base URL forms', () {
      const nativePath =
          '/api/v1/services/aigc/multimodal-generation/generation';
      expect(
        AlibabaQwenAsrProvider.nativeEndpointFor(
          'https://dashscope.aliyuncs.com/compatible-mode/v1',
        ),
        'https://dashscope.aliyuncs.com$nativePath',
      );
      expect(
        AlibabaQwenAsrProvider.nativeEndpointFor(
          'https://dashscope-intl.aliyuncs.com/api/v1',
        ),
        'https://dashscope-intl.aliyuncs.com$nativePath',
      );
      expect(
        AlibabaQwenAsrProvider.nativeEndpointFor(
          'https://dashscope.aliyuncs.com$nativePath',
        ),
        'https://dashscope.aliyuncs.com$nativePath',
      );
    });

    test('parses complete output text and sentence fallback', () {
      expect(
        AlibabaQwenAsrProvider.parseNativeTranscript(<String, dynamic>{
          'output': <String, dynamic>{'text': '完整文本'},
        }),
        '完整文本',
      );
      expect(
        AlibabaQwenAsrProvider.parseNativeTranscript(<String, dynamic>{
          'output': <String, dynamic>{
            'sentence': <String, dynamic>{'text': '句子文本'},
          },
        }),
        '句子文本',
      );
    });
  });

  group('AlibabaQwenAsrProvider OpenAI-compatible fallback', () {
    test('keeps Qwen3-ASR on the chat completions endpoint', () async {
      RequestOptions? capturedRequest;
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              capturedRequest = options;
              handler.resolve(
                Response<Map<String, dynamic>>(
                  requestOptions: options,
                  statusCode: 200,
                  data: <String, dynamic>{
                    'choices': <Map<String, dynamic>>[
                      <String, dynamic>{
                        'message': <String, dynamic>{'content': '兼容成功'},
                      },
                    ],
                  },
                ),
              );
            },
          ),
        );
      final directory = await Directory.systemTemp.createTemp(
        'voxwrite-qwen3-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final audio = File('${directory.path}/recording.wav');
      await audio.writeAsBytes(<int>[1, 2, 3, 4]);

      final transcript = await AlibabaQwenAsrProvider(
        dio: dio,
        apiKey: 'test-key',
        baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
        model: 'qwen3-asr-flash-2026-02-10',
      ).transcribe(audioPath: audio.path, locale: 'en_US');

      expect(transcript, '兼容成功');
      expect(
        capturedRequest?.uri.toString(),
        'https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions',
      );
      expect(capturedRequest?.headers['X-DashScope-SSE'], isNull);
      final data = capturedRequest?.data as Map<String, dynamic>;
      expect(data['model'], 'qwen3-asr-flash-2026-02-10');
      expect(data['asr_options'], <String, dynamic>{
        'enable_itn': true,
        'language': 'en',
      });
    });

    test('parses string content', () {
      final text = AlibabaQwenAsrProvider.parseTranscript(<String, dynamic>{
        'choices': <Map<String, dynamic>>[
          <String, dynamic>{
            'message': <String, dynamic>{'content': '你好，世界。'},
          },
        ],
      });

      expect(text, '你好，世界。');
    });

    test('parses multimodal content parts', () {
      final text = AlibabaQwenAsrProvider.parseTranscript(<String, dynamic>{
        'choices': <Map<String, dynamic>>[
          <String, dynamic>{
            'message': <String, dynamic>{
              'content': <Map<String, dynamic>>[
                <String, dynamic>{'type': 'text', 'text': '第一段'},
                <String, dynamic>{'type': 'text', 'text': '第二段'},
              ],
            },
          },
        ],
      });

      expect(text, '第一段第二段');
    });

    test('rejects an empty response', () {
      expect(
        () => AlibabaQwenAsrProvider.parseTranscript(<String, dynamic>{}),
        throwsA(isA<CloudProviderException>()),
      );
    });
  });

  test('speech settings default to Qwen-Audio 3.0 ASR Flash', () {
    const speech = SpeechProviderSettings();
    expect(
      speech.baseUrl,
      'https://dashscope.aliyuncs.com/compatible-mode/v1',
    );
    expect(speech.model, 'qwen-audio-3.0-asr-flash');
  });
}
