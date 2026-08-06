import 'voice_mode.dart';

class WritingRequest {
  const WritingRequest({
    required this.mode,
    required this.transcript,
    this.selectedText,
    this.targetLanguages = const [],
    this.personalDictionary = const [],
  });

  final VoiceMode mode;
  final String transcript;
  final String? selectedText;
  final List<String> targetLanguages;
  final List<String> personalDictionary;
}

abstract interface class WritingTransformer {
  Future<String> transform(WritingRequest request);
}

abstract interface class SpeechRecognizer {
  Future<String> transcribe({
    required String audioPath,
    String? locale,
    List<String> vocabulary = const [],
  });
}

abstract interface class TextDestination {
  Future<void> captureTarget();

  Future<String?> readSelection();

  Future<void> insert(String text);

  Future<void> clearTarget();
}
