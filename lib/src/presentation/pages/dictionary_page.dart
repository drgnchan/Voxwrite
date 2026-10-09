import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/personal_dictionary.dart';
import '../widgets/page_layout.dart';

class DictionaryPage extends ConsumerWidget {
  const DictionaryPage({super.key});

  Future<void> _addWord(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加词汇'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '名称或专有词',
            hintText: '例如：VoxWrite',
          ),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value != null) {
      await ref.read(personalDictionaryProvider.notifier).add(value);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dictionary = ref.watch(personalDictionaryProvider);

    return PageFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeader(
            title: '个人词典',
            description: '用于纠错和识别热词。',
            action: TextButton.icon(
              onPressed: dictionary.hasValue
                  ? () => _addWord(context, ref)
                  : null,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('添加词汇'),
            ),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: dictionary.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('无法读取个人词典：$error'),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () =>
                          ref.invalidate(personalDictionaryProvider),
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
              data: (words) => words.isEmpty
                  ? Center(
                      child: Text(
                        '还没有词汇',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.separated(
                      itemCount: words.length,
                      separatorBuilder: (_, _) => const Divider(),
                      itemBuilder: (context, index) {
                        final word = words[index];
                        return ListTile(
                          title: Text(word),
                          trailing: IconButton(
                            tooltip: '删除',
                            iconSize: 18,
                            visualDensity: VisualDensity.compact,
                            onPressed: () => ref
                                .read(personalDictionaryProvider.notifier)
                                .remove(word),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
