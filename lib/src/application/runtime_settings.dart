import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../infrastructure/providers/cloud_provider_settings.dart';

const translationTargetStorageKey = 'runtime_translation_target';
const runtimeCloudVendorStorageKey = 'runtime_cloud_vendor';
const runtimeCloudBaseUrlStorageKey = 'runtime_cloud_base_url';
const runtimeWritingModelStorageKey = 'runtime_writing_model';
const runtimeSpeechModelStorageKey = 'runtime_speech_model';
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
  });

  final CloudProviderSettings cloud;
  final bool globalShortcutEnabled;
  final bool autoStopOnSilence;
  final String translationTarget;

  RuntimeSettings copyWith({
    CloudProviderSettings? cloud,
    bool? globalShortcutEnabled,
    bool? autoStopOnSilence,
    String? translationTarget,
  }) {
    return RuntimeSettings(
      cloud: cloud ?? this.cloud,
      globalShortcutEnabled:
          globalShortcutEnabled ?? this.globalShortcutEnabled,
      autoStopOnSilence: autoStopOnSilence ?? this.autoStopOnSilence,
      translationTarget: translationTarget ?? this.translationTarget,
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
  );
}

final runtimeSettingsProvider =
    NotifierProvider<RuntimeSettingsController, RuntimeSettings>(
      RuntimeSettingsController.new,
    );

class RuntimeSettingsController extends Notifier<RuntimeSettings> {
  SharedPreferencesAsync? _preferencesInstance;

  SharedPreferencesAsync get _preferences =>
      _preferencesInstance ??= SharedPreferencesAsync();

  @override
  RuntimeSettings build() {
    unawaited(_load().catchError((_) {}));
    return const RuntimeSettings();
  }

  Future<void> _load() async {
    state = await loadRuntimeSettings(_preferences, defaults: state);
  }

  void setGlobalShortcutEnabled(bool enabled) {
    state = state.copyWith(globalShortcutEnabled: enabled);
    unawaited(_preferences.setBool(runtimeGlobalShortcutStorageKey, enabled));
  }

  void setAutoStopOnSilence(bool enabled) {
    state = state.copyWith(autoStopOnSilence: enabled);
    unawaited(_preferences.setBool(runtimeAutoStopStorageKey, enabled));
  }

  void setTranslationTarget(String target) {
    state = state.copyWith(translationTarget: target);
    unawaited(_preferences.setString(translationTargetStorageKey, target));
  }

  void setVendor(CloudProviderVendor vendor) {
    state = state.copyWith(
      cloud: state.cloud.copyWith(
        vendor: vendor,
        baseUrl: vendor.defaultBaseUrl,
        writingModel: vendor.defaultWritingModel,
        speechModel: vendor.defaultSpeechModel,
      ),
    );
    unawaited(_persistCloud());
  }

  void updateCloud({
    String? baseUrl,
    String? writingModel,
    String? speechModel,
  }) {
    state = state.copyWith(
      cloud: state.cloud.copyWith(
        baseUrl: baseUrl,
        writingModel: writingModel,
        speechModel: speechModel,
      ),
    );
    unawaited(_persistCloud());
  }

  Future<void> _persistCloud() async {
    final cloud = state.cloud;
    await Future.wait<void>([
      _preferences.setString(runtimeCloudVendorStorageKey, cloud.vendor.name),
      _preferences.setString(runtimeCloudBaseUrlStorageKey, cloud.baseUrl),
      _preferences.setString(runtimeWritingModelStorageKey, cloud.writingModel),
      _preferences.setString(runtimeSpeechModelStorageKey, cloud.speechModel),
    ]);
  }
}
