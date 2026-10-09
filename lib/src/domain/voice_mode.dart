enum VoiceMode { dictation, translation, ask }

extension VoiceModeText on VoiceMode {
  String get title => switch (this) {
    VoiceMode.dictation => '口述',
    VoiceMode.translation => '翻译',
    VoiceMode.ask => '问与改写',
  };

  String get shortcut => switch (this) {
    VoiceMode.dictation => 'Fn',
    VoiceMode.translation => 'Fn + Left Shift',
    VoiceMode.ask => 'Fn + Space',
  };

  String get f8Shortcut => switch (this) {
    VoiceMode.dictation => 'F8',
    VoiceMode.translation => 'Shift + F8',
    VoiceMode.ask => 'Ctrl + F8',
  };
}
