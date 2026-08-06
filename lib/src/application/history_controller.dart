import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../domain/history_entry.dart';
import '../domain/voice_mode.dart';

const historyStorageKey = 'voice_history_entries';
const maximumHistoryEntries = 200;

class HistoryStore {
  HistoryStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _preferences;

  Future<List<HistoryEntry>> load() async {
    final stored =
        await _preferences.getStringList(historyStorageKey) ?? const [];
    final entries = <HistoryEntry>[];
    for (final encoded in stored) {
      try {
        final json = jsonDecode(encoded);
        if (json is Map<String, dynamic>) {
          final entry = HistoryEntry.fromJson(json);
          if (entry != null) entries.add(entry);
        }
      } on FormatException {
        // Ignore one corrupt local record rather than hiding all history.
      }
    }
    entries.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return List<HistoryEntry>.unmodifiable(entries);
  }

  Future<List<HistoryEntry>> add({
    required VoiceMode mode,
    required String transcript,
    required String output,
  }) async {
    final entry = HistoryEntry(
      id: const Uuid().v4(),
      createdAt: DateTime.now(),
      mode: mode,
      transcript: transcript,
      output: output,
    );
    final next = <HistoryEntry>[
      entry,
      ...await load(),
    ].take(maximumHistoryEntries).toList(growable: false);
    await persist(next);
    return next;
  }

  Future<void> persist(List<HistoryEntry> entries) {
    return _preferences.setStringList(
      historyStorageKey,
      entries
          .map((entry) => jsonEncode(entry.toJson()))
          .toList(growable: false),
    );
  }

  Future<void> clear() => _preferences.remove(historyStorageKey);
}

final historyProvider =
    AsyncNotifierProvider<HistoryController, List<HistoryEntry>>(
      HistoryController.new,
    );

class HistoryController extends AsyncNotifier<List<HistoryEntry>> {
  late final HistoryStore _store = HistoryStore();

  @override
  Future<List<HistoryEntry>> build() => _store.load();

  Future<void> refresh() async {
    state = AsyncData(await _store.load());
  }

  Future<void> add({
    required VoiceMode mode,
    required String transcript,
    required String output,
  }) async {
    final next = await _store.add(
      mode: mode,
      transcript: transcript,
      output: output,
    );
    state = AsyncData(next);
  }

  Future<void> remove(String id) async {
    final current = state.value ?? await _store.load();
    final next = current
        .where((entry) => entry.id != id)
        .toList(growable: false);
    state = AsyncData(next);
    await _store.persist(next);
  }

  Future<void> clear() async {
    state = const AsyncData(<HistoryEntry>[]);
    await _store.clear();
  }
}
