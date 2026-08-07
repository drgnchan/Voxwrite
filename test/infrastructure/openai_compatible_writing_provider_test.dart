import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voxwrite/src/domain/voice_mode.dart';
import 'package:voxwrite/src/domain/writing_request.dart';
import 'package:voxwrite/src/infrastructure/providers/openai_compatible_writing_provider.dart';

void main() {
  test('sends the Qwen thinking switch when explicitly configured', () async {
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
                      'message': <String, dynamic>{'content': '整理后的文字。'},
                    },
                  ],
                },
              ),
            );
          },
        ),
      );
    final provider = OpenAiCompatibleWritingProvider(
      dio: dio,
      apiKey: 'test-key',
      baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
      model: 'qwen3.7-flash',
      enableThinking: false,
    );

    final result = await provider.transform(
      const WritingRequest(mode: VoiceMode.dictation, transcript: '测试文字'),
    );

    expect(result, '整理后的文字。');
    final data = capturedRequest?.data as Map<String, dynamic>;
    expect(data['model'], 'qwen3.7-flash');
    expect(data['enable_thinking'], isFalse);
  });

  test('omits the thinking switch for other compatible providers', () async {
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
                      'message': <String, dynamic>{'content': '完成'},
                    },
                  ],
                },
              ),
            );
          },
        ),
      );
    final provider = OpenAiCompatibleWritingProvider(
      dio: dio,
      apiKey: 'test-key',
      baseUrl: 'https://example.com/v1',
      model: 'custom-model',
    );

    await provider.transform(
      const WritingRequest(mode: VoiceMode.dictation, transcript: '测试文字'),
    );

    final data = capturedRequest?.data as Map<String, dynamic>;
    expect(data, isNot(contains('enable_thinking')));
  });
}
