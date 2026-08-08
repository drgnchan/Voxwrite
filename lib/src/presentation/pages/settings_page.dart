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

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final _apiKeyController = TextEditingController();
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
      final value = await ref
          .read(cloudApiKeyStoreProvider)
          .read()
          .timeout(const Duration(seconds: 5));
      if (mounted && value != null) _apiKeyController.text = value;
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

  Future<void> _saveKey() async {
    final value = _apiKeyController.text.trim();
    if (value.isEmpty) {
      setState(() => _storageError = 'API Key 不能为空。');
      return;
    }

    setState(() {
      _savingKey = true;
      _storageError = null;
    });
    try {
      final keyStore = ref.read(cloudApiKeyStoreProvider);
      await keyStore.write(value).timeout(const Duration(seconds: 8));
      final stored = await keyStore.read().timeout(const Duration(seconds: 5));
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
    _apiKeyController.dispose();
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
    final cloud = settings.cloud;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('设置', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 24),
              _SectionCard(
                title: '云端 Provider',
                subtitle: '文本处理采用 OpenAI 兼容接口；Qwen-Audio 语音识别自动改用百炼原生接口。',
                child: Column(
                  children: [
                    DropdownButtonFormField<CloudProviderVendor>(
                      initialValue: cloud.vendor,
                      decoration: const InputDecoration(
                        labelText: '服务商',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final vendor in CloudProviderVendor.values)
                          DropdownMenuItem(
                            value: vendor,
                            child: Text(vendor.label),
                          ),
                      ],
                      onChanged: (vendor) {
                        if (vendor != null) {
                          unawaited(controller.setVendor(vendor));
                        }
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      key: ValueKey('base-${cloud.vendor.name}'),
                      initialValue: cloud.baseUrl,
                      decoration: const InputDecoration(
                        labelText: '兼容接口 Base URL',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) {
                        unawaited(controller.updateCloud(baseUrl: value));
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      key: ValueKey('writing-${cloud.vendor.name}'),
                      initialValue: cloud.writingModel,
                      decoration: const InputDecoration(
                        labelText: '文本模型或 Endpoint ID',
                        hintText: '例如 qwen-plus',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) {
                        unawaited(controller.updateCloud(writingModel: value));
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      key: ValueKey('speech-${cloud.vendor.name}'),
                      initialValue: cloud.speechModel,
                      decoration: const InputDecoration(
                        labelText: '语音识别模型',
                        hintText: '推荐 qwen-audio-3.0-asr-flash',
                        helperText: '个人词典会作为即时热词提交给支持该能力的模型。',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) {
                        unawaited(controller.updateCloud(speechModel: value));
                      },
                    ),
                    const SizedBox(height: 14),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _apiKeyController,
                            obscureText: true,
                            decoration: const InputDecoration(
                              labelText: 'API Key',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        FilledButton(
                          onPressed: _savingKey ? null : _saveKey,
                          child: Text(_savingKey ? '保存中…' : '安全保存'),
                        ),
                      ],
                    ),
                    if (_storageError != null) ...[
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _storageError!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 18),
              _SectionCard(
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
                    helperText: '这是背景信息，不是要执行的指令；不要填写 API Key 或密码。',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                  onChanged: (value) {
                    unawaited(controller.updateDomainBackground(value));
                  },
                ),
              ),
              const SizedBox(height: 18),
              _SectionCard(
                title: '语音与语言',
                subtitle: '口述保持源语言；只有翻译模式使用下方目标语言。',
                child: Column(
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: settings.translationTarget,
                      decoration: const InputDecoration(
                        labelText: '翻译目标语言',
                        border: OutlineInputBorder(),
                      ),
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
                      subtitle: const Text('检测到语音后，连续静音约 1.4 秒自动处理；最长录音 2 分钟。'),
                      value: settings.autoStopOnSilence,
                      onChanged: (enabled) {
                        unawaited(controller.setAutoStopOnSilence(enabled));
                      },
                    ),
                  ],
                ),
              ),
              if (Platform.isMacOS || Platform.isWindows) ...[
                const SizedBox(height: 18),
                _SectionCard(
                  title: Platform.isWindows ? 'Windows 全局 F8' : 'macOS 全局 Fn',
                  subtitle: Platform.isWindows
                      ? 'Windows 不暴露硬件 Fn 键，因此使用 F8、Shift+F8 和 Ctrl+F8。'
                      : '默认开启；跨应用监听需要辅助功能和输入监控权限。关闭后不再监听 Fn。',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          Platform.isWindows
                              ? '监听全局 F8、Shift + F8、Ctrl + F8'
                              : '监听全局 Fn、Fn + Shift、Fn + Space',
                        ),
                        subtitle: const Text('启用后将控制录音、云端识别与文字写入。'),
                        value: settings.globalShortcutEnabled,
                        onChanged: (enabled) {
                          unawaited(
                            controller.setGlobalShortcutEnabled(enabled),
                          );
                        },
                      ),
                      if (_launchAtLoginSupported) ...[
                        const Divider(),
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('登录后自动启动 VoxWrite'),
                          subtitle: const Text('关闭主窗口后仍可从菜单栏重新打开。'),
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
                const SizedBox(height: 18),
                _SectionCard(
                  title: 'Android 输入法',
                  subtitle: '先在系统中启用 VoxWrite，再从输入法选择器切换。',
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () =>
                            AndroidPlatformBridge().openInputMethodSettings(),
                        icon: const Icon(Icons.settings_outlined),
                        label: const Text('启用输入法'),
                      ),
                      FilledButton.icon(
                        onPressed: () =>
                            AndroidPlatformBridge().showInputMethodPicker(),
                        icon: const Icon(Icons.keyboard_outlined),
                        label: const Text('选择 VoxWrite'),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 18),
              const _SectionCard(
                title: '目标平台',
                subtitle: '不包含 iOS。系统级输入能力由各平台原生实现。',
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    Chip(avatar: Icon(Icons.laptop_mac), label: Text('macOS')),
                    Chip(avatar: Icon(Icons.window), label: Text('Windows')),
                    Chip(
                      avatar: Icon(Icons.android),
                      label: Text('Android 输入法'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(subtitle),
            const SizedBox(height: 20),
            child,
          ],
        ),
      ),
    );
  }
}
