enum CloudProviderVendor { alibaba, doubao, deepseek, custom }

extension CloudProviderVendorDefaults on CloudProviderVendor {
  String get label => switch (this) {
    CloudProviderVendor.alibaba => '阿里云百炼',
    CloudProviderVendor.doubao => '豆包',
    CloudProviderVendor.deepseek => 'DeepSeek',
    CloudProviderVendor.custom => '自定义兼容接口',
  };

  String get defaultBaseUrl => switch (this) {
    CloudProviderVendor.alibaba =>
      'https://dashscope.aliyuncs.com/compatible-mode/v1',
    CloudProviderVendor.doubao => 'https://ark.cn-beijing.volces.com/api/v3',
    CloudProviderVendor.deepseek => 'https://api.deepseek.com',
    CloudProviderVendor.custom => '',
  };

  String get defaultWritingModel => switch (this) {
    CloudProviderVendor.alibaba => 'qwen-plus',
    CloudProviderVendor.doubao => '',
    CloudProviderVendor.deepseek => 'deepseek-v4-flash',
    CloudProviderVendor.custom => '',
  };
}

/// Extra request-body fields that switch the writing model into non-thinking
/// mode. Returns null for vendors whose API exposes no such switch, so the
/// request is sent without any thinking override.
extension CloudProviderVendorThinkingSwitch on CloudProviderVendor {
  Map<String, dynamic>? get disableThinkingFields => switch (this) {
    CloudProviderVendor.alibaba => <String, dynamic>{
      'enable_thinking': false,
    },
    CloudProviderVendor.deepseek => <String, dynamic>{
      'thinking': <String, String>{'type': 'disabled'},
    },
    CloudProviderVendor.doubao || CloudProviderVendor.custom => null,
  };
}

/// Speech recognition settings. Only the Alibaba Cloud Qwen-Audio adapter
/// exists today, so the vendor is fixed and only the endpoint and model are
/// configurable.
class SpeechProviderSettings {
  const SpeechProviderSettings({
    this.baseUrl = 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    this.model = 'qwen-audio-3.0-asr-flash',
  });

  final String baseUrl;
  final String model;

  SpeechProviderSettings copyWith({String? baseUrl, String? model}) {
    return SpeechProviderSettings(
      baseUrl: baseUrl ?? this.baseUrl,
      model: model ?? this.model,
    );
  }
}

/// Writing transformation settings for the OpenAI-compatible
/// `chat/completions` endpoint of the selected vendor.
class WritingProviderSettings {
  const WritingProviderSettings({
    this.vendor = CloudProviderVendor.alibaba,
    this.baseUrl = 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    this.model = 'qwen-plus',
  });

  final CloudProviderVendor vendor;
  final String baseUrl;
  final String model;

  WritingProviderSettings copyWith({
    CloudProviderVendor? vendor,
    String? baseUrl,
    String? model,
  }) {
    return WritingProviderSettings(
      vendor: vendor ?? this.vendor,
      baseUrl: baseUrl ?? this.baseUrl,
      model: model ?? this.model,
    );
  }
}
