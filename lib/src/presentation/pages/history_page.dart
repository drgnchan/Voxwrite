import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/history_controller.dart';
import '../../application/history_speech_controller.dart';
import '../../domain/history_entry.dart';
import '../../domain/voice_mode.dart';

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
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '历史记录',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
              if (history.value?.isNotEmpty == true)
                OutlinedButton.icon(
                  onPressed: () => _clearHistory(context, ref),
                  icon: const Icon(Icons.delete_sweep_outlined),
                  label: const Text('清空'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          const Text('仅在本机保存转写和最终文本，原始音频不会进入历史记录。'),
          const SizedBox(height: 24),
          Expanded(
            child: history.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(child: Text('无法读取历史记录：$error')),
              data: (entries) => entries.isEmpty
                  ? const _EmptyHistory()
                  : ListView.separated(
                      itemCount: entries.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) => _HistoryCard(
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

class _HistoryCard extends ConsumerWidget {
  const _HistoryCard({required this.entry, required this.onDelete});

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

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 560;
        return Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              ExpansionTile(
                leading: CircleAvatar(
                  child: Text(entry.mode.title.substring(0, 1)),
                ),
                title: SelectableText(entry.output),
                subtitle: Text(
                  '${entry.mode.title} · ${_formatTime(entry.createdAt)}',
                ),
                trailing: compact
                    ? null
                    : _HistoryActions(
                        entry: entry,
                        speech: speech,
                        isLoading: isLoading,
                        isPlaying: isPlaying,
                        onDelete: onDelete,
                        showLabels: false,
                      ),
                childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'ASR 原文',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SelectableText(entry.transcript),
                  ),
                ],
              ),
              if (compact) ...[
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: _HistoryActions(
                      entry: entry,
                      speech: speech,
                      isLoading: isLoading,
                      isPlaying: isPlaying,
                      onDelete: onDelete,
                      showLabels: true,
                    ),
                  ),
                ),
              ],
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
    required this.showLabels,
  });

  final HistoryEntry entry;
  final HistorySpeechState speech;
  final bool isLoading;
  final bool isPlaying;
  final VoidCallback onDelete;
  final bool showLabels;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final speechIcon = isLoading
        ? const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(
            isPlaying ? Icons.stop_circle_outlined : Icons.volume_up_outlined,
          );
    return Wrap(
      spacing: 2,
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _button(
          context: context,
          tooltip: isPlaying || isLoading ? '停止朗读' : '朗读最终文本',
          label: isLoading
              ? '生成中'
              : isPlaying
              ? '停止'
              : '朗读',
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
          context: context,
          tooltip: '复制结果',
          label: '复制',
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
          context: context,
          tooltip: '删除',
          label: '删除',
          icon: const Icon(Icons.delete_outline),
          isDestructive: true,
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
    required BuildContext context,
    required String tooltip,
    required String label,
    required Widget icon,
    required VoidCallback onPressed,
    bool isDestructive = false,
  }) {
    final color = isDestructive ? Theme.of(context).colorScheme.error : null;
    if (!showLabels) {
      return IconButton(
        tooltip: tooltip,
        color: color,
        onPressed: onPressed,
        icon: icon,
      );
    }
    return TextButton.icon(
      onPressed: onPressed,
      style: color == null
          ? null
          : TextButton.styleFrom(foregroundColor: color),
      icon: icon,
      label: Text(label),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.history_rounded,
            size: 52,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text('还没有历史记录', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text('完成的口述、翻译和问答会保存在本机。'),
        ],
      ),
    );
  }
}
