import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/voice_session_controller.dart';
import '../../domain/voice_mode.dart';
import '../../domain/voice_session.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(voiceSessionProvider);
    final availableModes = Platform.isAndroid
        ? VoiceMode.values.where((mode) => mode != VoiceMode.ask)
        : VoiceMode.values;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1040),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '开口起草，让文字自然成形',
                style: Theme.of(
                  context,
                ).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                Platform.isAndroid
                    ? '从常用输入法切换到 VoxWrite Voice，用声音完成整理和翻译。'
                    : '用声音完成整理、翻译和改写，结果会直接回到当前输入位置。',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 28),
              LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final columns = width > 820
                      ? 3
                      : width > 520
                      ? 2
                      : 1;
                  final cardWidth = (width - (columns - 1) * 16) / columns;
                  return Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      for (final mode in availableModes)
                        SizedBox(
                          width: cardWidth,
                          child: _ModeCard(
                            mode: mode,
                            selected: session.mode == mode && session.isBusy,
                            onPressed: () async {
                              await ref
                                  .read(voiceSessionProvider.notifier)
                                  .start(mode);
                            },
                          ),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 24),
              _SessionPanel(session: session),
              const SizedBox(height: 24),
              Card(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                child: const Padding(
                  padding: EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Icon(Icons.privacy_tip_outlined),
                      SizedBox(width: 14),
                      Expanded(child: Text('音频默认不写入历史。')),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.mode,
    required this.selected,
    required this.onPressed,
  });

  final VoiceMode mode;
  final bool selected;
  final VoidCallback onPressed;

  IconData get _icon => switch (mode) {
    VoiceMode.dictation => Icons.mic_none_rounded,
    VoiceMode.translation => Icons.translate_rounded,
    VoiceMode.ask => Icons.auto_awesome_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      color: selected ? colors.primaryContainer : colors.surface,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(18),
      ),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(_icon, size: 30, color: colors.primary),
              const SizedBox(height: 28),
              Text(
                mode.title,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(mode.description),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  Platform.isWindows || Platform.isLinux
                      ? mode.f8Shortcut
                      : Platform.isAndroid
                      ? 'Voice 输入'
                      : mode.shortcut,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SessionPanel extends ConsumerWidget {
  const _SessionPanel({required this.session});

  final VoiceSessionState session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(voiceSessionProvider.notifier);
    final (icon, title, detail) = switch (session.phase) {
      VoiceSessionPhase.idle => (
        Icons.check_circle_outline,
        '随时可以开始',
        Platform.isAndroid
            ? '在主输入法中选择 VoxWrite Voice，完成后会自动返回原键盘。'
            : '点击上方模式开始录音，也可以使用对应的全局快捷键。',
      ),
      VoiceSessionPhase.shortcutPreview => (
        Icons.keyboard_command_key,
        '模式已选定',
        Platform.isMacOS
            ? '松开 Fn 后开始录音；按 Shift 或 Space 可以切换模式。'
            : '松开 F8 后开始录音；按 Shift 或 Ctrl 可以切换模式。',
      ),
      VoiceSessionPhase.recording => (
        Icons.mic_rounded,
        '正在记录 · ${session.mode.title}',
        '说完后再次按下快捷键或点击停止；点击取消会丢弃本次录音。',
      ),
      VoiceSessionPhase.processing => (
        Icons.auto_awesome,
        '正在生成文字',
        '正在识别内容并整理表达。',
      ),
      VoiceSessionPhase.completed => (
        Icons.done_all,
        '文字已生成',
        session.output ?? '结果已写入当前应用。',
      ),
      VoiceSessionPhase.failed => (
        Icons.error_outline,
        '这次没有完成',
        session.failureMessage ?? '处理时遇到了问题，请重试。',
      ),
    };

    return Card(
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            CircleAvatar(child: Icon(icon)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 3),
                  Text(detail),
                ],
              ),
            ),
            if (session.phase == VoiceSessionPhase.recording)
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  FilledButton.icon(
                    onPressed: () async => controller.stopAndProcess(),
                    icon: const Icon(Icons.stop_rounded),
                    label: const Text('停止'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () async => controller.reset(),
                    icon: const Icon(Icons.close_rounded),
                    label: const Text('取消'),
                  ),
                ],
              )
            else if (session.phase != VoiceSessionPhase.idle)
              TextButton(
                onPressed: () async => controller.reset(),
                child: const Text('重置'),
              ),
          ],
        ),
      ),
    );
  }
}
