enum VoiceMode { dictation, translation, ask }

extension VoiceModeText on VoiceMode {
  String get title => switch (this) {
    VoiceMode.dictation => '口述',
    VoiceMode.translation => '翻译',
    VoiceMode.ask => '问与改写',
  };

  String get description => switch (this) {
    VoiceMode.dictation => '保留原意，自动去掉重复并补全标点与结构',
    VoiceMode.translation => '先理顺表达，再生成自然的目标语言文本',
    VoiceMode.ask => '对选中的内容提问、润色、压缩或重写',
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
