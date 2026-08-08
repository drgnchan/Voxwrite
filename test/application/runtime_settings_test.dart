import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:voxwrite/src/application/runtime_settings.dart';

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

    expect(settings.cloud.writingModel, 'qwen3.7-flash');
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
      controller.updateCloud(writingModel: 'qwen3'),
      controller.updateCloud(writingModel: 'qwen3.7'),
      controller.updateCloud(writingModel: 'qwen3.7-flash'),
    ];
    await Future.wait(writes);
    firstContainer.dispose();

    final restartedContainer = ProviderContainer();
    addTearDown(restartedContainer.dispose);
    final restored = await restartedContainer.read(
      runtimeSettingsProvider.future,
    );

    expect(restored.cloud.writingModel, 'qwen3.7-flash');
  });
}
