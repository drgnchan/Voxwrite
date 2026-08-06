import 'package:flutter_test/flutter_test.dart';
import 'package:voxwrite/src/domain/history_entry.dart';
import 'package:voxwrite/src/domain/voice_mode.dart';

void main() {
  test('history entry round-trips through local JSON', () {
    final entry = HistoryEntry(
      id: 'entry-1',
      createdAt: DateTime(2026, 8, 6, 10, 30),
      mode: VoiceMode.translation,
      transcript: '你好',
      output: 'Hello',
    );

    final restored = HistoryEntry.fromJson(entry.toJson());

    expect(restored, isNotNull);
    expect(restored!.id, entry.id);
    expect(restored.mode, VoiceMode.translation);
    expect(restored.transcript, '你好');
    expect(restored.output, 'Hello');
    expect(restored.createdAt, entry.createdAt);
  });
}
