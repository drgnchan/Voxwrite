import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'openai_compatible_writing_provider.dart';

/// Non-realtime speech synthesis through Alibaba Cloud Model Studio.
class AlibabaQwenTtsProvider {
  AlibabaQwenTtsProvider({
    required Dio dio,
    required this.apiKey,
    required this.baseUrl,
    this.model = 'qwen3-tts-instruct-flash',
    this.voice = 'Ethan',
    this.instructions =
        'Read in a formal, professional workplace tone. Use clear standard '
        'pronunciation, a steady moderate pace, and a confident, composed '
        'delivery. Do not sound theatrical or overly emotional.',
  }) : _dio = dio;

  final Dio _dio;
  final String apiKey;
  final String baseUrl;
  final String model;
  final String voice;
  final String instructions;

  Future<Uint8List> synthesize(String text) async {
    final normalizedText = text.trim();
    if (apiKey.trim().isEmpty) {
      throw const CloudProviderException('请先在设置中保存阿里云百炼 API Key。');
    }
    if (baseUrl.trim().isEmpty || model.trim().isEmpty) {
      throw const CloudProviderException('语音合成接口地址或模型为空。');
    }
    if (normalizedText.isEmpty) {
      throw const CloudProviderException('没有可朗读的文本。');
    }

    try {
      final response = await _dio.post<Map<String, dynamic>>(
        endpointFor(baseUrl),
        data: <String, dynamic>{
          'model': model.trim(),
          'input': <String, dynamic>{
            'text': normalizedText,
            'voice': voice,
            'language_type': 'Auto',
            'instructions': instructions,
            'optimize_instructions': true,
          },
        },
        options: Options(
          headers: <String, String>{
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
          sendTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(minutes: 2),
        ),
      );
      final audioUrl = parseAudioUrl(response.data);
      final audioResponse = await _dio.get<List<int>>(
        audioUrl,
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: const Duration(minutes: 2),
        ),
      );
      final bytes = audioResponse.data;
      if (bytes == null || bytes.isEmpty) {
        throw const CloudProviderException('语音合成返回了空音频。');
      }
      return Uint8List.fromList(bytes);
    } on DioException catch (error) {
      throw CloudProviderException(_requestErrorMessage(error));
    }
  }

  static String endpointFor(String baseUrl) {
    var root = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    const endpointPath =
        '/api/v1/services/aigc/multimodal-generation/generation';
    if (root.endsWith(endpointPath)) return root;
    root = root.replaceFirst(RegExp(r'/compatible-mode/v1$'), '');
    if (root.endsWith('/api/v1')) {
      return '$root/services/aigc/multimodal-generation/generation';
    }
    return '$root$endpointPath';
  }

  static String parseAudioUrl(Map<String, dynamic>? body) {
    final output = body?['output'];
    final audio = output is Map ? output['audio'] : null;
    final url = audio is Map ? audio['url'] : null;
    if (url is! String || url.trim().isEmpty) {
      throw const CloudProviderException('语音合成返回中缺少音频地址。');
    }
    return url.trim();
  }

  static String _requestErrorMessage(DioException error) {
    final statusCode = error.response?.statusCode;
    final body = error.response?.data;
    String? code;
    String? message;
    if (body is Map) {
      final rawCode = body['code'];
      final rawMessage = body['message'];
      if (rawCode is String && rawCode.trim().isNotEmpty) code = rawCode.trim();
      if (rawMessage is String && rawMessage.trim().isNotEmpty) {
        message = rawMessage.trim();
      }
    }
    final details = <String>[
      if (statusCode != null) 'HTTP $statusCode',
      ?code,
    ].join(' / ');
    final prefix = details.isEmpty ? '语音合成请求失败' : '语音合成请求失败（$details）';
    return message == null
        ? '$prefix，请检查网络、模型和阿里云 API Key。'
        : '$prefix：$message';
  }
}
