import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/writing_request.dart';
import '../infrastructure/audio/file_audio_capture.dart';
import '../infrastructure/platform/platform_text_destination.dart';

const cloudApiKeyStorageKey = 'cloud_provider_api_key_v2';
const _legacyCloudApiKeyStorageKey = 'cloud_provider_api_key';

final dioProvider = Provider<Dio>((ref) => Dio());

final secureStorageProvider = Provider<FlutterSecureStorage>(
  (ref) => const FlutterSecureStorage(
    mOptions: MacOsOptions(
      accountName: 'dev.raymond.voxwrite',
      usesDataProtectionKeychain: false,
    ),
  ),
);

/// Keeps the API key in memory after the first Keychain read. The cache lives
/// only for the current process and avoids a Keychain authorization dialog at
/// the end of every recording.
class CloudApiKeyStore {
  CloudApiKeyStore(this._storage);

  final FlutterSecureStorage _storage;
  String? _cachedValue;
  bool _hasCachedValue = false;
  Future<String?>? _pendingRead;

  Future<String?> read() {
    if (_hasCachedValue) return Future.value(_cachedValue);
    return _pendingRead ??= _readAndCache();
  }

  Future<String?> _readAndCache() async {
    try {
      var value = await _storage.read(key: cloudApiKeyStorageKey);
      if (value == null) {
        value = await _storage.read(key: _legacyCloudApiKeyStorageKey);
        if (value != null) {
          try {
            await _storage.write(key: cloudApiKeyStorageKey, value: value);
          } catch (_) {
            // The legacy item remains intact if migration cannot be written.
          }
        }
      }
      _cachedValue = value;
      _hasCachedValue = true;
      return value;
    } finally {
      _pendingRead = null;
    }
  }

  Future<void> write(String value) async {
    await _storage
        .write(key: cloudApiKeyStorageKey, value: value)
        .timeout(const Duration(seconds: 8));
    _cachedValue = value;
    _hasCachedValue = true;
  }
}

final cloudApiKeyStoreProvider = Provider<CloudApiKeyStore>(
  (ref) => CloudApiKeyStore(ref.read(secureStorageProvider)),
);

final audioCaptureProvider = Provider<AudioCapture>((ref) {
  final capture = FileAudioCapture();
  ref.onDispose(() => unawaited(capture.dispose()));
  return capture;
});

final textDestinationProvider = Provider<TextDestination>(
  (ref) => PlatformTextDestination(),
);
