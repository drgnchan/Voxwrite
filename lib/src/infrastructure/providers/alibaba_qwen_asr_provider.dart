import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '../../domain/writing_request.dart';
import 'openai_compatible_writing_provider.dart';

class AlibabaQwenAsrProvider implements SpeechRecognizer {
  AlibabaQwenAsrProvider({
    required Dio dio,
    required this.apiKey,
    required this.baseUrl,
    this.model = 'qwen3-asr-flash',
  }) : _dio = dio;

  static const int maxEncodedBytes = 10 * 1024 * 1024;

  final Dio _dio;
  final String apiKey;
  final String baseUrl;
  final String model;

  @override
  Future<String> transcribe({
    required String audioPath,
    String? locale,
    List<String> vocabulary = const [],
  }) async {
    if (apiKey.trim().isEmpty) {
      throw const CloudProviderException('请先在设置中保存阿里云百炼 API Key。');
    }
    if (baseUrl.trim().isEmpty || model.trim().isEmpty) {
      throw const CloudProviderException('请配置阿里云接口地址和语音识别模型。');
    }

    final bytes = await File(audioPath).readAsBytes();
    final encoded = base64Encode(bytes);
    if (encoded.length > maxEncodedBytes) {
      throw const CloudProviderException(
        '录音过长：Base64 编码后超过阿里云 10 MB 限制，请分段口述。',
      );
    }

    final language = _languageCode(locale);
    final response = await _dio.post<Map<String, dynamic>>(
      '${baseUrl.replaceFirst(RegExp(r'/$'), '')}/chat/completions',
      data: <String, dynamic>{
        'model': model,
        'messages': <Map<String, dynamic>>[
          <String, dynamic>{
            'role': 'user',
            'content': <Map<String, dynamic>>[
              <String, dynamic>{
                'type': 'input_audio',
                'input_audio': <String, String>{
                  'data': 'data:audio/wav;base64,$encoded',
                },
              },
            ],
          },
        ],
        'stream': false,
        'asr_options': <String, dynamic>{
          'enable_itn': true,
          ...?language == null ? null : <String, String>{'language': language},
        },
      },
      options: Options(
        headers: <String, String>{
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        sendTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(minutes: 2),
      ),
    );

    return parseTranscript(response.data);
  }

  static String parseTranscript(Map<String, dynamic>? body) {
    final choices = body?['choices'];
    if (choices is! List || choices.isEmpty) {
      throw const CloudProviderException('语音识别返回中没有候选结果。');
    }
    final first = choices.first;
    if (first is! Map) {
      throw const CloudProviderException('语音识别返回格式不受支持。');
    }
    final message = first['message'];
    if (message is! Map) {
      throw const CloudProviderException('语音识别返回中缺少消息。');
    }
    final content = message['content'];
    final text = switch (content) {
      String value => value,
      List value =>
        value
            .whereType<Map>()
            .map((part) => part['text'])
            .whereType<String>()
            .join(),
      _ => '',
    };
    if (text.trim().isEmpty) {
      throw const CloudProviderException('没有识别到可用语音。');
    }
    return text.trim();
  }

  static String? _languageCode(String? locale) {
    if (locale == null || locale.trim().isEmpty) return null;
    final normalized = locale.toLowerCase();
    if (normalized.startsWith('zh')) return 'zh';
    if (normalized.startsWith('en')) return 'en';
    if (normalized.startsWith('ja')) return 'ja';
    if (normalized.startsWith('ko')) return 'ko';
    return null;
  }
}
