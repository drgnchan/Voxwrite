import '../domain/voice_mode.dart';
import '../domain/writing_request.dart';

class WritingPromptBuilder {
  const WritingPromptBuilder();

  String systemPrompt(WritingRequest request) {
    final dictionary = request.personalDictionary.isEmpty
        ? ''
        : '''
个人词典（精确拼写）：${request.personalDictionary.join('、')}。
若语音转写中出现与词典词汇发音相近的同音字、错误空格、大小写或连字符，结合上下文纠正为词典中的精确拼写；没有发音依据时不要强行插入。''';

    final modeInstruction = switch (request.mode) {
      VoiceMode.dictation =>
        '''
你是语音写作编辑器。把口语转写整理成可以直接发送或发布的文字：
- 忠实保留原意，不增加事实。
- 删除口头禅、无意义停顿和重复，但保留有意强调。
- 自动补全标点，按语义分段；明确的步骤使用列表。
- 保留说话者的语气，不把自然表达改成公文。
- 保持语音转写的原始语言；除非说话者明确要求，否则不要翻译。
- 只输出最终文字，不解释你的修改。''',
      VoiceMode.translation =>
        '''
你是专业本地化编辑器。将口语内容翻译成自然、地道、可以直接使用的目标语言文本：
- 忠实保留信息、语气和格式意图。
- 先消除口头语和重复，再进行翻译。
- 不逐字硬译，不增加事实。
- 只输出翻译结果。''',
      VoiceMode.ask =>
        '''
你是上下文写作助手。根据用户的语音指令和可选的选中文本完成提问、总结、改写或编辑：
- 若用户要求改写，优先只输出可直接替换原文的结果。
- 若用户提出问题，给出直接、清晰的答案。
- 不编造选中文本中不存在的事实。
- 除非用户要求，否则不要解释处理过程。''',
    };

    return '$modeInstruction$dictionary';
  }

  String userPrompt(WritingRequest request) {
    final targets = request.targetLanguages.isEmpty
        ? ''
        : '\n目标语言：${request.targetLanguages.join('、')}';
    final selection =
        request.selectedText == null || request.selectedText!.trim().isEmpty
        ? ''
        : '\n\n当前选中文本：\n${request.selectedText!.trim()}';

    return '''语音转写：
${request.transcript.trim()}$targets$selection''';
  }
}
