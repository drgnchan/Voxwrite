import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../infrastructure/providers/cloud_provider_settings.dart';

const translationTargetStorageKey = 'runtime_translation_target';
const runtimeCloudVendorStorageKey = 'runtime_cloud_vendor';
const runtimeCloudBaseUrlStorageKey = 'runtime_cloud_base_url';
const runtimeWritingModelStorageKey = 'runtime_writing_model';
const runtimeSpeechModelStorageKey = 'runtime_speech_model';
const runtimeDomainBackgroundStorageKey = 'runtime_domain_background';
const runtimeGlobalShortcutStorageKey = 'runtime_global_shortcut';
const runtimeAutoStopStorageKey = 'runtime_auto_stop_silence';

const supportedTranslationTargets = <String>[
  'English',
  '简体中文',
  '繁體中文',
  '日本語',
  '한국어',
  'Español',
  'Français',
  'Deutsch',
];

class RuntimeSettings {
  const RuntimeSettings({
    this.cloud = const CloudProviderSettings(),
    this.globalShortcutEnabled = true,
    this.autoStopOnSilence = true,
    this.translationTarget = 'English',
    this.domainBackground = '',
  });

  final CloudProviderSettings cloud;
  final bool globalShortcutEnabled;
  final bool autoStopOnSilence;
  final String translationTarget;
  final String domainBackground;

  RuntimeSettings copyWith({
    CloudProviderSettings? cloud,
    bool? globalShortcutEnabled,
    bool? autoStopOnSilence,
    String? translationTarget,
    String? domainBackground,
  }) {
    return RuntimeSettings(
      cloud: cloud ?? this.cloud,
      globalShortcutEnabled:
          globalShortcutEnabled ?? this.globalShortcutEnabled,
      autoStopOnSilence: autoStopOnSilence ?? this.autoStopOnSilence,
      translationTarget: translationTarget ?? this.translationTarget,
      domainBackground: domainBackground ?? this.domainBackground,
    );
  }
}

Future<RuntimeSettings> loadRuntimeSettings(
  SharedPreferencesAsync preferences, {
  RuntimeSettings defaults = const RuntimeSettings(),
}) async {
  final vendorName = await preferences.getString(runtimeCloudVendorStorageKey);
  final vendor = CloudProviderVendor.values
      .where((value) => value.name == vendorName)
      .firstOrNull;
  final selectedVendor = vendor ?? defaults.cloud.vendor;
  return RuntimeSettings(
    cloud: CloudProviderSettings(
      vendor: selectedVendor,
      baseUrl:
          await preferences.getString(runtimeCloudBaseUrlStorageKey) ??
          selectedVendor.defaultBaseUrl,
      writingModel:
          await preferences.getString(runtimeWritingModelStorageKey) ??
          selectedVendor.defaultWritingModel,
      speechModel:
          await preferences.getString(runtimeSpeechModelStorageKey) ??
          selectedVendor.defaultSpeechModel,
    ),
    globalShortcutEnabled:
        await preferences.getBool(runtimeGlobalShortcutStorageKey) ??
        defaults.globalShortcutEnabled,
    autoStopOnSilence:
        await preferences.getBool(runtimeAutoStopStorageKey) ??
        defaults.autoStopOnSilence,
    translationTarget:
        await preferences.getString(translationTargetStorageKey) ??
        defaults.translationTarget,
    domainBackground:
        await preferences.getString(runtimeDomainBackgroundStorageKey) ??
        defaults.domainBackground,
  );
}

final runtimeSettingsProvider =
    AsyncNotifierProvider<RuntimeSettingsController, RuntimeSettings>(
      RuntimeSettingsController.new,
    );

class RuntimeSettingsController extends AsyncNotifier<RuntimeSettings> {
  SharedPreferencesAsync? _preferencesInstance;
  Future<void> _writeQueue = Future<void>.value();

  SharedPreferencesAsync get _preferences =>
      _preferencesInstance ??= SharedPreferencesAsync();

  @override
  Future<RuntimeSettings> build() => loadRuntimeSettings(_preferences);

  Future<void> setGlobalShortcutEnabled(bool enabled) {
    final current = state.requireValue;
    state = AsyncData(current.copyWith(globalShortcutEnabled: enabled));
    return _enqueueWrite(
      () => _preferences.setBool(runtimeGlobalShortcutStorageKey, enabled),
    );
  }

  Future<void> setAutoStopOnSilence(bool enabled) {
    final current = state.requireValue;
    state = AsyncData(current.copyWith(autoStopOnSilence: enabled));
    return _enqueueWrite(
      () => _preferences.setBool(runtimeAutoStopStorageKey, enabled),
    );
  }

  Future<void> setTranslationTarget(String target) {
    final current = state.requireValue;
    state = AsyncData(current.copyWith(translationTarget: target));
    return _enqueueWrite(
      () => _preferences.setString(translationTargetStorageKey, target),
    );
  }

  Future<void> updateDomainBackground(String background) {
    final current = state.requireValue;
    state = AsyncData(current.copyWith(domainBackground: background));
    return _enqueueWrite(
      () =>
          _preferences.setString(runtimeDomainBackgroundStorageKey, background),
    );
  }

  Future<void> setVendor(CloudProviderVendor vendor) {
    final current = state.requireValue;
    final cloud = current.cloud.copyWith(
      vendor: vendor,
      baseUrl: vendor.defaultBaseUrl,
      writingModel: vendor.defaultWritingModel,
      speechModel: vendor.defaultSpeechModel,
    );
    state = AsyncData(current.copyWith(cloud: cloud));
    return _enqueueWrite(() => _persistCloud(cloud));
  }

  Future<void> updateCloud({
    String? baseUrl,
    String? writingModel,
    String? speechModel,
  }) {
    final current = state.requireValue;
    final cloud = current.cloud.copyWith(
      baseUrl: baseUrl,
      writingModel: writingModel,
      speechModel: speechModel,
    );
    state = AsyncData(current.copyWith(cloud: cloud));
    return _enqueueWrite(() async {
      if (baseUrl != null) {
        await _preferences.setString(runtimeCloudBaseUrlStorageKey, baseUrl);
      }
      if (writingModel != null) {
        await _preferences.setString(
          runtimeWritingModelStorageKey,
          writingModel,
        );
      }
      if (speechModel != null) {
        await _preferences.setString(runtimeSpeechModelStorageKey, speechModel);
      }
    });
  }

  Future<void> _enqueueWrite(Future<void> Function() write) {
    final operation = _writeQueue.then((_) => write());
    _writeQueue = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  Future<void> _persistCloud(CloudProviderSettings cloud) async {
    await Future.wait<void>([
      _preferences.setString(runtimeCloudVendorStorageKey, cloud.vendor.name),
      _preferences.setString(runtimeCloudBaseUrlStorageKey, cloud.baseUrl),
      _preferences.setString(runtimeWritingModelStorageKey, cloud.writingModel),
      _preferences.setString(runtimeSpeechModelStorageKey, cloud.speechModel),
    ]);
  }
}
