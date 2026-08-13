import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../infrastructure/providers/cloud_provider_settings.dart';

const translationTargetStorageKey = 'runtime_translation_target';
const runtimeCloudVendorStorageKey = 'runtime_cloud_vendor';
const runtimeCloudBaseUrlStorageKey = 'runtime_cloud_base_url';
const runtimeWritingModelStorageKey = 'runtime_writing_model';
const runtimeSpeechBaseUrlStorageKey = 'runtime_speech_base_url';
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
    this.writing = const WritingProviderSettings(),
    this.speech = const SpeechProviderSettings(),
    this.globalShortcutEnabled = true,
    this.autoStopOnSilence = true,
    this.translationTarget = 'English',
    this.domainBackground = '',
  });

  final WritingProviderSettings writing;
  final SpeechProviderSettings speech;
  final bool globalShortcutEnabled;
  final bool autoStopOnSilence;
  final String translationTarget;
  final String domainBackground;

  RuntimeSettings copyWith({
    WritingProviderSettings? writing,
    SpeechProviderSettings? speech,
    bool? globalShortcutEnabled,
    bool? autoStopOnSilence,
    String? translationTarget,
    String? domainBackground,
  }) {
    return RuntimeSettings(
      writing: writing ?? this.writing,
      speech: speech ?? this.speech,
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
  final writingVendor = vendor ?? defaults.writing.vendor;
  return RuntimeSettings(
    writing: WritingProviderSettings(
      vendor: writingVendor,
      baseUrl:
          await preferences.getString(runtimeCloudBaseUrlStorageKey) ??
          writingVendor.defaultBaseUrl,
      model:
          await preferences.getString(runtimeWritingModelStorageKey) ??
          writingVendor.defaultWritingModel,
    ),
    speech: SpeechProviderSettings(
      baseUrl:
          await preferences.getString(runtimeSpeechBaseUrlStorageKey) ??
          defaults.speech.baseUrl,
      model:
          await preferences.getString(runtimeSpeechModelStorageKey) ??
          defaults.speech.model,
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

  Future<void> setWritingVendor(CloudProviderVendor vendor) {
    final current = state.requireValue;
    final writing = current.writing.copyWith(
      vendor: vendor,
      baseUrl: vendor.defaultBaseUrl,
      model: vendor.defaultWritingModel,
    );
    state = AsyncData(current.copyWith(writing: writing));
    return _enqueueWrite(() => _persistWriting(writing));
  }

  Future<void> updateWriting({String? baseUrl, String? model}) {
    final current = state.requireValue;
    final writing = current.writing.copyWith(baseUrl: baseUrl, model: model);
    state = AsyncData(current.copyWith(writing: writing));
    return _enqueueWrite(() async {
      if (baseUrl != null) {
        await _preferences.setString(runtimeCloudBaseUrlStorageKey, baseUrl);
      }
      if (model != null) {
        await _preferences.setString(runtimeWritingModelStorageKey, model);
      }
    });
  }

  Future<void> updateSpeech({String? baseUrl, String? model}) {
    final current = state.requireValue;
    final speech = current.speech.copyWith(baseUrl: baseUrl, model: model);
    state = AsyncData(current.copyWith(speech: speech));
    return _enqueueWrite(() async {
      if (baseUrl != null) {
        await _preferences.setString(runtimeSpeechBaseUrlStorageKey, baseUrl);
      }
      if (model != null) {
        await _preferences.setString(runtimeSpeechModelStorageKey, model);
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

  Future<void> _persistWriting(WritingProviderSettings writing) async {
    await Future.wait<void>([
      _preferences.setString(runtimeCloudVendorStorageKey, writing.vendor.name),
      _preferences.setString(runtimeCloudBaseUrlStorageKey, writing.baseUrl),
      _preferences.setString(runtimeWritingModelStorageKey, writing.model),
    ]);
  }
}
