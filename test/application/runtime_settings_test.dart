import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:voxwrite/src/application/runtime_settings.dart';
import 'package:voxwrite/src/infrastructure/providers/cloud_provider_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test('loads the persisted writing model before exposing settings', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData(<String, Object>{
          runtimeCloudVendorStorageKey: 'alibaba',
          runtimeCloudBaseUrlStorageKey:
              'https://dashscope.aliyuncs.com/compatible-mode/v1',
          runtimeWritingModelStorageKey: 'qwen3.7-flash',
          runtimeSpeechModelStorageKey: 'qwen-audio-3.0-asr-flash',
        });
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final settings = await container.read(runtimeSettingsProvider.future);

    expect(settings.writing.model, 'qwen3.7-flash');
  });

  test('keeps speech settings independent when the writing vendor changes',
      () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(runtimeSettingsProvider.future);
    final controller = container.read(runtimeSettingsProvider.notifier);

    await controller.setWritingVendor(CloudProviderVendor.deepseek);

    final settings = container.read(runtimeSettingsProvider).requireValue;
    expect(settings.writing.vendor, CloudProviderVendor.deepseek);
    expect(settings.writing.baseUrl, 'https://api.deepseek.com');
    expect(settings.writing.model, 'deepseek-v4-flash');
    // Speech recognition stays on Alibaba Qwen-Audio.
    expect(
      settings.speech.baseUrl,
      'https://dashscope.aliyuncs.com/compatible-mode/v1',
    );
    expect(settings.speech.model, 'qwen-audio-3.0-asr-flash');
  });

  test('persists and restores independent speech and writing settings',
      () async {
    final firstContainer = ProviderContainer();
    await firstContainer.read(runtimeSettingsProvider.future);
    final controller = firstContainer.read(runtimeSettingsProvider.notifier);

    await controller.setWritingVendor(CloudProviderVendor.deepseek);
    await controller.updateWriting(model: 'deepseek-v4-flash-custom');
    await controller.updateSpeech(model: 'qwen3-asr-flash');
    await controller.updateSpeech(
      baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    );
    firstContainer.dispose();

    final restartedContainer = ProviderContainer();
    addTearDown(restartedContainer.dispose);
    final restored = await restartedContainer.read(
      runtimeSettingsProvider.future,
    );

    expect(restored.writing.vendor, CloudProviderVendor.deepseek);
    expect(restored.writing.baseUrl, 'https://api.deepseek.com');
    expect(restored.writing.model, 'deepseek-v4-flash-custom');
    expect(restored.speech.model, 'qwen3-asr-flash');
    expect(
      restored.speech.baseUrl,
      'https://dashscope.aliyuncs.com/compatible-mode/v1',
    );
  });

  test('persists and restores the domain background', () async {
    final firstContainer = ProviderContainer();
    await firstContainer.read(runtimeSettingsProvider.future);
    final controller = firstContainer.read(runtimeSettingsProvider.notifier);

    await controller.updateDomainBackground('主要做 Flutter 和 Android 开发');
    firstContainer.dispose();

    final restartedContainer = ProviderContainer();
    addTearDown(restartedContainer.dispose);
    final restored = await restartedContainer.read(
      runtimeSettingsProvider.future,
    );

    expect(restored.domainBackground, '主要做 Flutter 和 Android 开发');
  });

  test('serializes model auto-saves and restores the latest value', () async {
    final firstContainer = ProviderContainer();
    await firstContainer.read(runtimeSettingsProvider.future);
    final controller = firstContainer.read(runtimeSettingsProvider.notifier);

    final writes = <Future<void>>[
      controller.updateWriting(model: 'qwen3'),
      controller.updateWriting(model: 'qwen3.7'),
      controller.updateWriting(model: 'qwen3.7-flash'),
    ];
    await Future.wait(writes);
    firstContainer.dispose();

    final restartedContainer = ProviderContainer();
    addTearDown(restartedContainer.dispose);
    final restored = await restartedContainer.read(
      runtimeSettingsProvider.future,
    );

    expect(restored.writing.model, 'qwen3.7-flash');
  });
}
