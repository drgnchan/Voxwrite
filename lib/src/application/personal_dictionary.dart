import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const personalDictionaryStorageKey = 'personal_dictionary_words';

final personalDictionaryProvider =
    AsyncNotifierProvider<PersonalDictionaryController, List<String>>(
      PersonalDictionaryController.new,
    );

class PersonalDictionaryController extends AsyncNotifier<List<String>> {
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();

  @override
  Future<List<String>> build() async {
    final stored =
        await _preferences.getStringList(personalDictionaryStorageKey) ??
        const <String>[];
    return _normalized(stored);
  }

  Future<void> add(String value) async {
    final word = value.trim();
    if (word.isEmpty) return;
    final current = state.value ?? await build();
    if (current.any((item) => item.toLowerCase() == word.toLowerCase())) return;
    final next = <String>[...current, word];
    state = AsyncData(next);
    await _preferences.setStringList(personalDictionaryStorageKey, next);
  }

  Future<void> remove(String value) async {
    final current = state.value ?? await build();
    final next = current.where((item) => item != value).toList(growable: false);
    state = AsyncData(next);
    await _preferences.setStringList(personalDictionaryStorageKey, next);
  }

  List<String> _normalized(List<String> values) {
    final result = <String>[];
    final seen = <String>{};
    for (final value in values) {
      final word = value.trim();
      if (word.isEmpty || !seen.add(word.toLowerCase())) continue;
      result.add(word);
    }
    return List<String>.unmodifiable(result);
  }
}
