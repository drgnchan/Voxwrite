import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voxwrite/src/domain/voice_mode.dart';
import 'package:voxwrite/src/domain/writing_request.dart';
import 'package:voxwrite/src/infrastructure/providers/cloud_provider_settings.dart';
import 'package:voxwrite/src/infrastructure/providers/openai_compatible_writing_provider.dart';

typedef RequestCapture = ({RequestOptions? Function() request, Dio dio});

RequestCapture _capturingDio() {
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
  return (request: () => capturedRequest, dio: dio);
}

OpenAiCompatibleWritingProvider _provider(
  Dio dio, {
  Map<String, dynamic>? extraBody,
}) {
  return OpenAiCompatibleWritingProvider(
    dio: dio,
    apiKey: 'test-key',
    baseUrl: 'https://api.deepseek.com',
    model: 'deepseek-v4-flash',
    extraBody: extraBody,
  );
}

void main() {
  test('sends the Qwen thinking switch for Alibaba', () async {
    final capture = _capturingDio();
    final provider = _provider(
      capture.dio,
      extraBody: CloudProviderVendor.alibaba.disableThinkingFields,
    );

    final result = await provider.transform(
      const WritingRequest(mode: VoiceMode.dictation, transcript: '测试文字'),
    );

    expect(result, '整理后的文字。');
    final data = capture.request()?.data as Map<String, dynamic>;
    expect(data['model'], 'deepseek-v4-flash');
    expect(data['enable_thinking'], isFalse);
    expect(data, isNot(contains('thinking')));
  });

  test('sends the DeepSeek thinking switch set to disabled', () async {
    final capture = _capturingDio();
    final provider = _provider(
      capture.dio,
      extraBody: CloudProviderVendor.deepseek.disableThinkingFields,
    );

    await provider.transform(
      const WritingRequest(mode: VoiceMode.dictation, transcript: '测试文字'),
    );

    final data = capture.request()?.data as Map<String, dynamic>;
    expect(
      data['thinking'],
      <String, String>{'type': 'disabled'},
    );
    expect(data, isNot(contains('enable_thinking')));
  });

  test('omits the thinking switch when no vendor fields are configured', () async {
    final capture = _capturingDio();
    final provider = _provider(capture.dio);

    await provider.transform(
      const WritingRequest(mode: VoiceMode.dictation, transcript: '测试文字'),
    );

    final data = capture.request()?.data as Map<String, dynamic>;
    expect(data, isNot(contains('enable_thinking')));
    expect(data, isNot(contains('thinking')));
  });
}
