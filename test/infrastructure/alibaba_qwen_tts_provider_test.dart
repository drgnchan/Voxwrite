import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voxwrite/src/infrastructure/providers/alibaba_qwen_tts_provider.dart';
import 'package:voxwrite/src/infrastructure/providers/openai_compatible_writing_provider.dart';

void main() {
  test('synthesizes formal male speech and downloads returned audio', () async {
    RequestOptions? synthesisRequest;
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.uri.host == 'audio.example.com') {
              handler.resolve(
                Response<List<int>>(
                  requestOptions: options,
                  statusCode: 200,
                  data: <int>[1, 2, 3, 4],
                ),
              );
              return;
            }
            synthesisRequest = options;
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                statusCode: 200,
                data: <String, dynamic>{
                  'output': <String, dynamic>{
                    'audio': <String, dynamic>{
                      'url': 'https://audio.example.com/result.wav',
                    },
                  },
                },
              ),
            );
          },
        ),
      );

    final audio = await AlibabaQwenTtsProvider(
      dio: dio,
      apiKey: 'test-key',
      baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1/',
    ).synthesize('Hello from VoxWrite.');

    expect(audio, Uint8List.fromList(<int>[1, 2, 3, 4]));
    expect(
      synthesisRequest?.uri.toString(),
      'https://dashscope.aliyuncs.com/api/v1/services/aigc/multimodal-generation/generation',
    );
    expect(synthesisRequest?.headers['Authorization'], 'Bearer test-key');
    final body = synthesisRequest?.data as Map<String, dynamic>;
    expect(body['model'], 'qwen3-tts-instruct-flash');
    final input = body['input'] as Map<String, dynamic>;
    expect(input['text'], 'Hello from VoxWrite.');
    expect(input['voice'], 'Ethan');
    expect(input['language_type'], 'Auto');
    expect(input['instructions'], contains('formal, professional workplace'));
    expect(input['optimize_instructions'], isTrue);
  });

  test('rejects a response without an audio URL', () {
    expect(
      () => AlibabaQwenTtsProvider.parseAudioUrl(<String, dynamic>{
        'output': <String, dynamic>{},
      }),
      throwsA(isA<CloudProviderException>()),
    );
  });
}
