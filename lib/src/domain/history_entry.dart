import 'voice_mode.dart';

class HistoryEntry {
  const HistoryEntry({
    required this.id,
    required this.createdAt,
    required this.mode,
    required this.transcript,
    required this.output,
  });

  final String id;
  final DateTime createdAt;
  final VoiceMode mode;
  final String transcript;
  final String output;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'mode': mode.name,
    'transcript': transcript,
    'output': output,
  };

  static HistoryEntry? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final createdAt = DateTime.tryParse(json['createdAt'] as String? ?? '');
    final modeName = json['mode'];
    final transcript = json['transcript'];
    final output = json['output'];
    if (id is! String ||
        createdAt == null ||
        modeName is! String ||
        transcript is! String ||
        output is! String) {
      return null;
    }
    final mode = VoiceMode.values
        .where((value) => value.name == modeName)
        .firstOrNull;
    if (mode == null) return null;
    return HistoryEntry(
      id: id,
      createdAt: createdAt.toLocal(),
      mode: mode,
      transcript: transcript,
      output: output,
    );
  }
}
