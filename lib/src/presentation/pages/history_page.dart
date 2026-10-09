import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/history_controller.dart';
import '../../application/history_speech_controller.dart';
import '../../domain/history_entry.dart';
import '../../domain/voice_mode.dart';
import '../widgets/page_layout.dart';

class HistoryPage extends ConsumerStatefulWidget {
  const HistoryPage({super.key});

  @override
  ConsumerState<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends ConsumerState<HistoryPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(historyProvider.notifier).refresh();
    });
  }

  Future<void> _clearHistory(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空历史记录？'),
        content: const Text('只会删除本机保存的文字记录，无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final speech = ref.read(historySpeechProvider.notifier);
      await speech.stop();
      await ref.read(historyProvider.notifier).clear();
      await speech.clearCachedAudio();
    }
  }

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(historyProvider);
    return PageFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeader(
            title: '历史记录',
            action: history.value?.isNotEmpty == true
                ? TextButton(
                    onPressed: () => _clearHistory(context, ref),
                    child: const Text('清空'),
                  )
                : null,
          ),
          const SizedBox(height: 24),
          Expanded(
            child: history.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(child: Text('无法读取历史记录：$error')),
              data: (entries) => entries.isEmpty
                  ? const _EmptyHistory()
                  : ListView.separated(
                      itemCount: entries.length,
                      separatorBuilder: (_, _) => const Divider(),
                      itemBuilder: (context, index) => _HistoryItem(
                        entry: entries[index],
                        onDelete: () => ref
                            .read(historyProvider.notifier)
                            .remove(entries[index].id),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryItem extends ConsumerWidget {
  const _HistoryItem({required this.entry, required this.onDelete});

  final HistoryEntry entry;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final speech = ref.watch(historySpeechProvider);
    final isLoading =
        speech.entryId == entry.id &&
        speech.phase == HistorySpeechPhase.loading;
    final isPlaying =
        speech.entryId == entry.id &&
        speech.phase == HistorySpeechPhase.playing;
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 560;
        final actions = _HistoryActions(
          entry: entry,
          speech: speech,
          isLoading: isLoading,
          isPlaying: isPlaying,
          onDelete: onDelete,
        );
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            children: [
              ExpansionTile(
                title: SelectableText(entry.output),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '${entry.mode.title} · ${_formatTime(entry.createdAt)}',
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                ),
                trailing: compact ? null : actions,
                expandedAlignment: Alignment.centerLeft,
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ASR 原文',
                    style: theme.textTheme.labelMedium?.copyWith(color: muted),
                  ),
                  const SizedBox(height: 6),
                  SelectableText(
                    entry.transcript,
                    style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                  ),
                ],
              ),
              if (compact)
                Align(alignment: Alignment.centerRight, child: actions),
            ],
          ),
        );
      },
    );
  }

  String _formatTime(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)} '
        '${two(value.hour)}:${two(value.minute)}';
  }
}

class _HistoryActions extends ConsumerWidget {
  const _HistoryActions({
    required this.entry,
    required this.speech,
    required this.isLoading,
    required this.isPlaying,
    required this.onDelete,
  });

  final HistoryEntry entry;
  final HistorySpeechState speech;
  final bool isLoading;
  final bool isPlaying;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final speechIcon = isLoading
        ? const SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(isPlaying ? Icons.stop_rounded : Icons.volume_up_outlined);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _button(
          tooltip: isPlaying || isLoading ? '停止朗读' : '朗读最终文本',
          icon: speechIcon,
          onPressed: () async {
            try {
              await ref.read(historySpeechProvider.notifier).toggle(entry);
            } catch (error) {
              if (context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('无法朗读：$error')));
              }
            }
          },
        ),
        _button(
          tooltip: '复制结果',
          icon: const Icon(Icons.copy_outlined),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: entry.output));
            if (context.mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('已复制最终文本')));
            }
          },
        ),
        _button(
          tooltip: '删除',
          icon: const Icon(Icons.delete_outline),
          onPressed: () async {
            if (speech.entryId == entry.id) {
              await ref.read(historySpeechProvider.notifier).stop();
            }
            onDelete();
            await ref
                .read(historySpeechProvider.notifier)
                .removeCachedAudio(entry.id);
          },
        ),
      ],
    );
  }

  Widget _button({
    required String tooltip,
    required Widget icon,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      tooltip: tooltip,
      iconSize: 20,
      visualDensity: VisualDensity.compact,
      onPressed: onPressed,
      icon: icon,
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Text(
        '还没有历史记录',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
