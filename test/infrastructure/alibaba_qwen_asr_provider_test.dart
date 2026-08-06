import 'package:flutter_test/flutter_test.dart';
import 'package:voxwrite/src/infrastructure/providers/alibaba_qwen_asr_provider.dart';
import 'package:voxwrite/src/infrastructure/providers/openai_compatible_writing_provider.dart';

void main() {
  group('AlibabaQwenAsrProvider.parseTranscript', () {
    test('parses OpenAI-compatible string content', () {
      final text = AlibabaQwenAsrProvider.parseTranscript(<String, dynamic>{
        'choices': <Map<String, dynamic>>[
          <String, dynamic>{
            'message': <String, dynamic>{'content': '你好，世界。'},
          },
        ],
      });

      expect(text, '你好，世界。');
    });

    test('parses multimodal content parts', () {
      final text = AlibabaQwenAsrProvider.parseTranscript(<String, dynamic>{
        'choices': <Map<String, dynamic>>[
          <String, dynamic>{
            'message': <String, dynamic>{
              'content': <Map<String, dynamic>>[
                <String, dynamic>{'type': 'text', 'text': '第一段'},
                <String, dynamic>{'type': 'text', 'text': '第二段'},
              ],
            },
          },
        ],
      });

      expect(text, '第一段第二段');
    });

    test('rejects an empty response', () {
      expect(
        () => AlibabaQwenAsrProvider.parseTranscript(<String, dynamic>{}),
        throwsA(isA<CloudProviderException>()),
      );
    });
  });
}
