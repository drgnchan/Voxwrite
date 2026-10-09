import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/voice_session_controller.dart';
import '../../domain/voice_mode.dart';
import '../../domain/voice_session.dart';
import '../widgets/page_layout.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(voiceSessionProvider);
    final availableModes = Platform.isAndroid
        ? VoiceMode.values.where((mode) => mode != VoiceMode.ask)
        : VoiceMode.values;
    final theme = Theme.of(context);
    return PageFrame(
      scrollable: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PageHeader(title: '开口起草，让文字自然成形'),
          const SizedBox(height: 28),
          for (final mode in availableModes)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: _ModeRow(
                mode: mode,
                selected: session.mode == mode && session.isBusy,
                onPressed: () async {
                  await ref.read(voiceSessionProvider.notifier).start(mode);
                },
              ),
            ),
          const SizedBox(height: 28),
          const Divider(),
          const SizedBox(height: 24),
          _SessionStatus(session: session),
          const SizedBox(height: 40),
          Text(
            '音频默认不写入历史。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeRow extends StatelessWidget {
  const _ModeRow({
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

  String? get _shortcut => Platform.isAndroid
      ? null
      : Platform.isWindows || Platform.isLinux
      ? mode.f8Shortcut
      : mode.shortcut;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    const radius = BorderRadius.all(Radius.circular(12));
    return Material(
      color: selected ? colors.surfaceContainer : Colors.transparent,
      borderRadius: radius,
      child: InkWell(
        onTap: onPressed,
        borderRadius: radius,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              Icon(
                _icon,
                size: 22,
                color: selected ? colors.onSurface : colors.onSurfaceVariant,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  mode.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (_shortcut case final shortcut?) ...[
                const SizedBox(width: 16),
                Text(
                  shortcut,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SessionStatus extends ConsumerWidget {
  const _SessionStatus({required this.session});

  final VoiceSessionState session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(voiceSessionProvider.notifier);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final (title, detail) = switch (session.phase) {
      VoiceSessionPhase.idle => (
        '随时可以开始',
        Platform.isAndroid
            ? '在主输入法中选择 VoxWrite Voice，完成后会自动返回原键盘。'
            : '点击上方模式开始录音，也可以使用对应的全局快捷键。',
      ),
      VoiceSessionPhase.shortcutPreview => (
        '模式已选定',
        Platform.isMacOS
            ? '松开 Fn 后开始录音；按 Shift 或 Space 可以切换模式。'
            : '松开 F8 后开始录音；按 Shift 或 Ctrl 可以切换模式。',
      ),
      VoiceSessionPhase.recording => (
        '正在记录 · ${session.mode.title}',
        '说完后再次按下快捷键或点击停止；点击取消会丢弃本次录音。',
      ),
      VoiceSessionPhase.processing => ('正在生成文字', '正在识别内容并整理表达。'),
      VoiceSessionPhase.completed => ('文字已生成', session.output ?? '结果已写入当前应用。'),
      VoiceSessionPhase.failed => (
        '这次没有完成',
        session.failureMessage ?? '处理时遇到了问题，请重试。',
      ),
    };
    final dotColor = switch (session.phase) {
      VoiceSessionPhase.idle => colors.outline,
      VoiceSessionPhase.recording || VoiceSessionPhase.failed => colors.error,
      _ => colors.onSurface,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 7),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
                child: const SizedBox.square(dimension: 8),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    detail,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (session.phase != VoiceSessionPhase.idle) ...[
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.only(left: 22),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (session.phase == VoiceSessionPhase.recording) ...[
                  FilledButton(
                    onPressed: () async => controller.stopAndProcess(),
                    child: const Text('停止'),
                  ),
                  TextButton(
                    onPressed: () async => controller.reset(),
                    child: const Text('取消'),
                  ),
                ] else
                  TextButton(
                    onPressed: () async => controller.reset(),
                    child: const Text('重置'),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
