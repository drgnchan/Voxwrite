import 'package:flutter_test/flutter_test.dart';
import 'package:voxwrite/src/application/writing_prompt_builder.dart';
import 'package:voxwrite/src/domain/voice_mode.dart';
import 'package:voxwrite/src/domain/writing_request.dart';

void main() {
  const builder = WritingPromptBuilder();

  test('dictation prompt protects meaning and personal vocabulary', () {
    const request = WritingRequest(
      mode: VoiceMode.dictation,
      transcript: '那个 VoxWrite 明天上线',
      personalDictionary: ['VoxWrite'],
    );

    final system = builder.systemPrompt(request);

    expect(system, contains('不增加事实'));
    expect(system, contains('保持语音转写的原始语言'));
    expect(system, contains('个人词典（精确拼写）'));
    expect(system, contains('同音字、错误空格、大小写或连字符'));
    expect(system, isNot(contains('默认输出语言')));
    expect(system, isNot(contains('zh-CN')));
    expect(system, contains('VoxWrite'));
    expect(builder.userPrompt(request), contains('那个 VoxWrite 明天上线'));
  });

  test('translation prompt is the only mode with a target language', () {
    const request = WritingRequest(
      mode: VoiceMode.translation,
      transcript: '你好',
      targetLanguages: ['English'],
    );

    final system = builder.systemPrompt(request);
    final user = builder.userPrompt(request);

    expect(system, contains('目标语言'));
    expect(user, contains('目标语言：English'));
  });

  test('ask prompt includes selected text as context', () {
    const request = WritingRequest(
      mode: VoiceMode.ask,
      transcript: '帮我改得更有说服力',
      selectedText: '我们应该试试看。',
    );

    final user = builder.userPrompt(request);

    expect(user, contains('帮我改得更有说服力'));
    expect(user, contains('当前选中文本'));
    expect(user, contains('我们应该试试看。'));
  });
}
