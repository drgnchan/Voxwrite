import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/personal_dictionary.dart';

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

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '个人词典',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
              FilledButton.icon(
                onPressed: dictionary.hasValue
                    ? () => _addWord(context, ref)
                    : null,
                icon: const Icon(Icons.add),
                label: const Text('添加词汇'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text('专有词会在文字整理时纠正同音字、大小写、空格和连字符，并为支持热词的 ASR 提供词表。'),
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
                    OutlinedButton(
                      onPressed: () =>
                          ref.invalidate(personalDictionaryProvider),
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
              data: (words) => words.isEmpty
                  ? const Center(child: Text('还没有词汇'))
                  : ListView.separated(
                      itemCount: words.length,
                      separatorBuilder: (_, _) => const Divider(),
                      itemBuilder: (context, index) {
                        final word = words[index];
                        return ListTile(
                          leading: const Icon(Icons.spellcheck_rounded),
                          title: Text(word),
                          trailing: IconButton(
                            tooltip: '删除',
                            onPressed: () => ref
                                .read(personalDictionaryProvider.notifier)
                                .remove(word),
                            icon: const Icon(Icons.delete_outline),
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
