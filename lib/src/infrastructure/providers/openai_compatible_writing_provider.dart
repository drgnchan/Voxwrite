import 'package:dio/dio.dart';

import '../../application/writing_prompt_builder.dart';
import '../../domain/writing_request.dart';

class OpenAiCompatibleWritingProvider implements WritingTransformer {
  OpenAiCompatibleWritingProvider({
    required Dio dio,
    required this.apiKey,
    required this.baseUrl,
    required this.model,
    WritingPromptBuilder promptBuilder = const WritingPromptBuilder(),
  }) : _dio = dio,
       _promptBuilder = promptBuilder;

  final Dio _dio;
  final WritingPromptBuilder _promptBuilder;
  final String apiKey;
  final String baseUrl;
  final String model;

  @override
  Future<String> transform(WritingRequest request) async {
    if (apiKey.trim().isEmpty) {
      throw const CloudProviderException('请先配置 API Key。');
    }
    if (baseUrl.trim().isEmpty || model.trim().isEmpty) {
      throw const CloudProviderException('请配置接口地址和文本模型。');
    }

    final response = await _dio.post<Map<String, dynamic>>(
      '${baseUrl.replaceFirst(RegExp(r'/$'), '')}/chat/completions',
      data: <String, dynamic>{
        'model': model,
        'temperature': 0.2,
        'messages': <Map<String, String>>[
          <String, String>{
            'role': 'system',
            'content': _promptBuilder.systemPrompt(request),
          },
          <String, String>{
            'role': 'user',
            'content': _promptBuilder.userPrompt(request),
          },
        ],
      },
      options: Options(
        headers: <String, String>{
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        sendTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 60),
      ),
    );

    final choices = response.data?['choices'];
    if (choices is! List || choices.isEmpty) {
      throw const CloudProviderException('云端返回中没有生成结果。');
    }
    final first = choices.first;
    if (first is! Map<String, dynamic>) {
      throw const CloudProviderException('云端返回格式不受支持。');
    }
    final message = first['message'];
    if (message is! Map<String, dynamic>) {
      throw const CloudProviderException('云端返回中缺少消息。');
    }
    final content = message['content'];
    if (content is! String || content.trim().isEmpty) {
      throw const CloudProviderException('云端返回了空文本。');
    }
    return content.trim();
  }
}

class CloudProviderException implements Exception {
  const CloudProviderException(this.message);

  final String message;

  @override
  String toString() => message;
}
