enum CloudProviderVendor { alibaba, doubao, custom }

extension CloudProviderVendorDefaults on CloudProviderVendor {
  String get label => switch (this) {
    CloudProviderVendor.alibaba => '阿里云百炼',
    CloudProviderVendor.doubao => '豆包',
    CloudProviderVendor.custom => '自定义兼容接口',
  };

  String get defaultBaseUrl => switch (this) {
    CloudProviderVendor.alibaba =>
      'https://dashscope.aliyuncs.com/compatible-mode/v1',
    CloudProviderVendor.doubao => 'https://ark.cn-beijing.volces.com/api/v3',
    CloudProviderVendor.custom => '',
  };

  String get defaultWritingModel => switch (this) {
    CloudProviderVendor.alibaba => 'qwen-plus',
    CloudProviderVendor.doubao => '',
    CloudProviderVendor.custom => '',
  };

  String get defaultSpeechModel => switch (this) {
    CloudProviderVendor.alibaba => 'qwen-audio-3.0-asr-flash',
    CloudProviderVendor.doubao => '',
    CloudProviderVendor.custom => '',
  };
}

class CloudProviderSettings {
  const CloudProviderSettings({
    this.vendor = CloudProviderVendor.alibaba,
    this.baseUrl = 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    this.writingModel = 'qwen-plus',
    this.speechModel = 'qwen-audio-3.0-asr-flash',
  });

  final CloudProviderVendor vendor;
  final String baseUrl;
  final String writingModel;
  final String speechModel;

  CloudProviderSettings copyWith({
    CloudProviderVendor? vendor,
    String? baseUrl,
    String? writingModel,
    String? speechModel,
  }) {
    return CloudProviderSettings(
      vendor: vendor ?? this.vendor,
      baseUrl: baseUrl ?? this.baseUrl,
      writingModel: writingModel ?? this.writingModel,
      speechModel: speechModel ?? this.speechModel,
    );
  }
}
