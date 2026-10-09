import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/runtime_settings.dart';
import '../../application/workflow_dependencies.dart';
import '../../infrastructure/platform/android_platform_bridge.dart';
import '../../infrastructure/platform/global_shortcut_bridge.dart';
import '../../infrastructure/platform/platform_lifecycle_bridge.dart';
import '../../infrastructure/providers/cloud_provider_settings.dart';
import '../widgets/page_layout.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final _speechApiKeyController = TextEditingController();
  final _writingApiKeyController = TextEditingController();
  final _lifecycleBridge = PlatformLifecycleBridge();
  bool _savingKey = false;
  bool _launchAtLoginSupported = false;
  bool _launchAtLoginEnabled = false;
  bool _updatingLaunchAtLogin = false;
  String? _storageError;
  String? _lifecycleError;

  @override
  void initState() {
    super.initState();
    unawaited(_loadKey());
    unawaited(_loadLifecycleSettings());
  }

  Future<void> _loadKey() async {
    try {
      final speechValue = await ref
          .read(cloudApiKeyStoreProvider)
          .read()
          .timeout(const Duration(seconds: 5));
      final writingValue = await ref
          .read(writingApiKeyStoreProvider)
          .read()
          .timeout(const Duration(seconds: 5));
      if (mounted) {
        if (speechValue != null) _speechApiKeyController.text = speechValue;
        if (writingValue != null) _writingApiKeyController.text = writingValue;
      }
    } on TimeoutException {
      if (mounted) {
        setState(() => _storageError = '读取系统安全存储超时，请重启应用后重试。');
      }
    } catch (error) {
      if (mounted) {
        setState(() => _storageError = '无法读取系统安全存储：$error');
      }
    }
  }

  Future<void> _loadLifecycleSettings() async {
    final supported = await _lifecycleBridge.isLaunchAtLoginSupported();
    final enabled = supported
        ? await _lifecycleBridge.isLaunchAtLoginEnabled()
        : false;
    if (mounted) {
      setState(() {
        _launchAtLoginSupported = supported;
        _launchAtLoginEnabled = enabled;
      });
    }
  }

  Future<void> _setLaunchAtLogin(bool enabled) async {
    setState(() {
      _updatingLaunchAtLogin = true;
      _lifecycleError = null;
    });
    try {
      final actual = await _lifecycleBridge.setLaunchAtLogin(enabled);
      if (mounted) setState(() => _launchAtLoginEnabled = actual);
    } catch (error) {
      if (mounted) {
        setState(() => _lifecycleError = '无法更新开机启动：$error');
      }
    } finally {
      if (mounted) setState(() => _updatingLaunchAtLogin = false);
    }
  }

  Future<void> _saveKey(
    CloudApiKeyStore store,
    TextEditingController controller, {
    required String emptyMessage,
  }) async {
    final value = controller.text.trim();
    if (value.isEmpty) {
      setState(() => _storageError = emptyMessage);
      return;
    }

    setState(() {
      _savingKey = true;
      _storageError = null;
    });
    try {
      await store.write(value).timeout(const Duration(seconds: 8));
      final stored = await store.read().timeout(const Duration(seconds: 5));
      if (stored != value) {
        throw StateError('Keychain 写入后读回校验失败');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('API Key 已保存到系统安全存储。')));
    } on TimeoutException {
      if (mounted) {
        setState(() => _storageError = '保存超时。请重启应用后重试，不会继续无限等待。');
      }
    } catch (error) {
      if (mounted) {
        setState(() => _storageError = '保存失败：$error');
      }
    } finally {
      if (mounted) setState(() => _savingKey = false);
    }
  }

  @override
  void dispose() {
    _speechApiKeyController.dispose();
    _writingApiKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settingsState = ref.watch(runtimeSettingsProvider);
    final controller = ref.read(runtimeSettingsProvider.notifier);
    final settings = settingsState.value;
    if (settings == null) {
      return Center(
        child: settingsState.hasError
            ? Text('读取本机设置失败：${settingsState.error}')
            : const CircularProgressIndicator(),
      );
    }
    final writing = settings.writing;
    final speech = settings.speech;

    return PageFrame(
      scrollable: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PageHeader(title: '设置'),
          const SizedBox(height: 32),
          _Section(
            title: '语音识别',
            child: Column(
              children: [
                TextFormField(
                  key: const ValueKey('speech-base'),
                  initialValue: speech.baseUrl,
                  decoration: const InputDecoration(labelText: '百炼 Base URL'),
                  onChanged: (value) {
                    unawaited(controller.updateSpeech(baseUrl: value));
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  key: const ValueKey('speech-model'),
                  initialValue: speech.model,
                  decoration: const InputDecoration(
                    labelText: '语音识别模型',
                    hintText: '推荐 qwen-audio-3.0-asr-flash',
                  ),
                  onChanged: (value) {
                    unawaited(controller.updateSpeech(model: value));
                  },
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _speechApiKeyController,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: '阿里云百炼 API Key',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: _savingKey
                          ? null
                          : () => _saveKey(
                              ref.read(cloudApiKeyStoreProvider),
                              _speechApiKeyController,
                              emptyMessage: 'API Key 不能为空。',
                            ),
                      child: Text(_savingKey ? '保存中…' : '安全保存'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const _SectionDivider(),
          _Section(
            title: '文本模型',
            child: Column(
              children: [
                DropdownButtonFormField<CloudProviderVendor>(
                  initialValue: writing.vendor,
                  decoration: const InputDecoration(labelText: '服务商'),
                  items: [
                    for (final vendor in CloudProviderVendor.values)
                      DropdownMenuItem(
                        value: vendor,
                        child: Text(vendor.label),
                      ),
                  ],
                  onChanged: (vendor) {
                    if (vendor != null) {
                      unawaited(controller.setWritingVendor(vendor));
                    }
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  key: ValueKey('writing-base-${writing.vendor.name}'),
                  initialValue: writing.baseUrl,
                  decoration: const InputDecoration(labelText: '兼容接口 Base URL'),
                  onChanged: (value) {
                    unawaited(controller.updateWriting(baseUrl: value));
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  key: ValueKey('writing-model-${writing.vendor.name}'),
                  initialValue: writing.model,
                  decoration: const InputDecoration(
                    labelText: '文本模型或 Endpoint ID',
                    hintText: '例如 qwen-plus 或 deepseek-v4-flash',
                  ),
                  onChanged: (value) {
                    unawaited(controller.updateWriting(model: value));
                  },
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _writingApiKeyController,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: '文本模型 API Key',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: _savingKey
                          ? null
                          : () => _saveKey(
                              ref.read(writingApiKeyStoreProvider),
                              _writingApiKeyController,
                              emptyMessage: 'API Key 不能为空。',
                            ),
                      child: Text(_savingKey ? '保存中…' : '安全保存'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_storageError != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _storageError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ],
          const _SectionDivider(),
          _Section(
            title: '领域背景',
            subtitle: '填写你的专业领域或技术栈，帮助识别和整理专业术语。',
            child: TextFormField(
              key: const ValueKey('domain-background'),
              initialValue: settings.domainBackground,
              minLines: 3,
              maxLines: 6,
              maxLength: 1000,
              decoration: const InputDecoration(
                labelText: '领域背景',
                hintText: '例如：我主要做 Flutter、Dart 和 Android 开发。',
                helperText: '不要填写 API Key 或密码。',
                alignLabelWithHint: true,
              ),
              onChanged: (value) {
                unawaited(controller.updateDomainBackground(value));
              },
            ),
          ),
          const _SectionDivider(),
          _Section(
            title: '语音与语言',
            child: Column(
              children: [
                DropdownButtonFormField<String>(
                  initialValue: settings.translationTarget,
                  decoration: const InputDecoration(labelText: '翻译目标语言'),
                  items: [
                    for (final target in supportedTranslationTargets)
                      DropdownMenuItem(value: target, child: Text(target)),
                  ],
                  onChanged: (target) {
                    if (target != null) {
                      unawaited(controller.setTranslationTarget(target));
                    }
                  },
                ),
                const SizedBox(height: 10),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('说完后自动停止'),
                  subtitle: const Text('静音约 1.4 秒后自动处理，最长 2 分钟。'),
                  value: settings.autoStopOnSilence,
                  onChanged: (enabled) {
                    unawaited(controller.setAutoStopOnSilence(enabled));
                  },
                ),
              ],
            ),
          ),
          if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) ...[
            const _SectionDivider(),
            _Section(
              title: Platform.isLinux
                  ? 'Linux 全局 F8'
                  : Platform.isWindows
                  ? 'Windows 全局 F8'
                  : 'macOS 全局 Fn',
              subtitle: Platform.isLinux
                  ? 'X11 自动回填，Wayland 需开启下方选项，否则复制到剪贴板。'
                  : Platform.isMacOS
                  ? '需要辅助功能和输入监控权限。'
                  : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      Platform.isWindows || Platform.isLinux
                          ? '监听全局 F8、Shift + F8、Ctrl + F8'
                          : '监听全局 Fn、Fn + Shift、Fn + Space',
                    ),
                    value: settings.globalShortcutEnabled,
                    onChanged: (enabled) {
                      unawaited(controller.setGlobalShortcutEnabled(enabled));
                    },
                  ),
                  if (Platform.isLinux) ...[
                    const Divider(),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Wayland 自动回填'),
                      subtitle: const Text(
                        '需安装 ydotool、wl-clipboard 并启用 ydotool 服务。',
                      ),
                      value: settings.waylandBackfill,
                      onChanged: (enabled) {
                        unawaited(controller.setWaylandBackfill(enabled));
                      },
                    ),
                  ],
                  if (_launchAtLoginSupported) ...[
                    const Divider(),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('登录后自动启动 VoxWrite'),
                      value: _launchAtLoginEnabled,
                      onChanged: _updatingLaunchAtLogin
                          ? null
                          : _setLaunchAtLogin,
                    ),
                  ],
                  if (_lifecycleError != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      _lifecycleError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  if (Platform.isMacOS) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () async {
                            await GlobalShortcutBridge()
                                .openAccessibilitySettings();
                          },
                          icon: const Icon(Icons.lock_open_outlined),
                          label: const Text('打开辅助功能设置'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () async {
                            await GlobalShortcutBridge()
                                .openInputMonitoringSettings();
                          },
                          icon: const Icon(Icons.keyboard_alt_outlined),
                          label: const Text('打开输入监控设置'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
          if (Platform.isAndroid) ...[
            const _SectionDivider(),
            _Section(
              title: 'Android 语音输入',
              subtitle: '完成或取消后会自动返回原键盘。',
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  OutlinedButton.icon(
                    onPressed: () =>
                        AndroidPlatformBridge().openInputMethodSettings(),
                    icon: const Icon(Icons.settings_voice_outlined),
                    label: const Text('启用 VoxWrite Voice'),
                  ),
                  FilledButton.icon(
                    onPressed: () =>
                        AndroidPlatformBridge().showInputMethodPicker(),
                    icon: const Icon(Icons.keyboard_outlined),
                    label: const Text('选择主输入法'),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.subtitle});

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 20),
        child,
      ],
    );
  }
}

class _SectionDivider extends StatelessWidget {
  const _SectionDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 32),
      child: Divider(),
    );
  }
}
