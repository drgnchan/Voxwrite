import 'package:flutter_test/flutter_test.dart';
import 'package:voxwrite/src/infrastructure/providers/cloud_provider_settings.dart';

void main() {
  group('DeepSeek defaults', () {
    const vendor = CloudProviderVendor.deepseek;

    test('uses the official OpenAI-compatible base URL', () {
      expect(vendor.defaultBaseUrl, 'https://api.deepseek.com');
    });

    test('defaults to DeepSeek V4 Flash', () {
      expect(vendor.defaultWritingModel, 'deepseek-v4-flash');
    });
  });

  group('WritingProviderSettings', () {
    test('defaults to Alibaba with qwen-plus', () {
      const writing = WritingProviderSettings();
      expect(writing.vendor, CloudProviderVendor.alibaba);
      expect(
        writing.baseUrl,
        'https://dashscope.aliyuncs.com/compatible-mode/v1',
      );
      expect(writing.model, 'qwen-plus');
    });

    test('copyWith only replaces the vendor', () {
      const writing = WritingProviderSettings();
      final deepseek = writing.copyWith(vendor: CloudProviderVendor.deepseek);
      expect(deepseek.vendor, CloudProviderVendor.deepseek);
      expect(
        deepseek.baseUrl,
        'https://dashscope.aliyuncs.com/compatible-mode/v1',
      );
      expect(deepseek.model, 'qwen-plus');
    });
  });

  group('SpeechProviderSettings', () {
    test('defaults to the Alibaba Qwen-Audio endpoint and model', () {
      const speech = SpeechProviderSettings();
      expect(
        speech.baseUrl,
        'https://dashscope.aliyuncs.com/compatible-mode/v1',
      );
      expect(speech.model, 'qwen-audio-3.0-asr-flash');
    });

    test('updates independently of the writing provider', () {
      const speech = SpeechProviderSettings();
      final updated = speech.copyWith(model: 'qwen3-asr-flash');
      expect(updated.model, 'qwen3-asr-flash');
      expect(
        updated.baseUrl,
        'https://dashscope.aliyuncs.com/compatible-mode/v1',
      );
    });
  });

  test('DeepSeek thinking switch explicitly disables thinking', () {
    expect(
      CloudProviderVendor.deepseek.disableThinkingFields,
      <String, dynamic>{
        'thinking': <String, String>{'type': 'disabled'},
      },
    );
  });

  test('vendors without a thinking switch leave the request body unchanged', () {
    expect(CloudProviderVendor.doubao.disableThinkingFields, isNull);
    expect(CloudProviderVendor.custom.disableThinkingFields, isNull);
  });
}
