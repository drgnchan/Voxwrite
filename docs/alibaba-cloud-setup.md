# 阿里云百炼配置

VoxWrite 默认接入阿里云百炼：

- 语音识别：`qwen-audio-3.0-asr-flash`
- 文字整理：`qwen-plus`
- 文字整理使用 OpenAI 兼容 `chat/completions`
- Qwen-Audio 语音识别使用 DashScope 原生多模态生成接口

## 设置项

在 VoxWrite → 设置中填写：

| 设置 | 推荐值 |
| --- | --- |
| 服务商 | 阿里云百炼 |
| Base URL | `https://dashscope.aliyuncs.com/compatible-mode/v1` |
| 文本模型 | `qwen-plus` |
| 语音识别模型 | `qwen-audio-3.0-asr-flash` |
| API Key | 从百炼控制台创建的 Key |

如果当前业务空间要求专属地址，请将 Base URL 改为：

```text
https://{WorkspaceId}.cn-beijing.maas.aliyuncs.com/compatible-mode/v1
```

VoxWrite 会保留该地址供文本模型使用，并自动将 Qwen-Audio 的语音请求转换到同一域名下的原生端点：

```text
https://{WorkspaceId}.cn-beijing.maas.aliyuncs.com/api/v1/services/aigc/multimodal-generation/generation
```

新加坡等其他地域需要使用对应地域的业务空间域名和 API Key。API Key 只保存在系统安全存储中，不写入项目文件或普通偏好设置。

## 模型兼容性

- `qwen-audio-3.0-asr-flash`：默认模型，使用原生 HTTP 协议，支持即时热词和语言提示。
- `qwen3-asr-flash-2026-02-10`：兼容回退，继续使用 OpenAI 兼容协议。
- `qwen3-asr-flash`：仍可使用，但当前稳定别名对应较早的快照。
- Qwen-Audio 的 `streaming` 和 `filetrans` 变体调用流程不同，当前不在此同步短音频适配器的支持范围内。

使用默认 Qwen-Audio 模型时，个人词典会去重后作为权重为 5 的即时热词提交，以改善人名、产品名和技术术语的识别。

## 领域背景

设置页中的“领域背景”用于填写当前专业领域和常见技术上下文，例如“我主要做 Flutter、Dart 和 Android 开发”。保存后，VoxWrite 会将它作为非指令性的上下文注入语音识别请求和文字整理提示，帮助模型区分专业术语、英文缩写和同音词。

领域背景不是个人词典：个人词典适合放必须保留精确拼写的名称和术语；领域背景适合描述工作领域、技术栈和表达习惯。不要在其中填写 API Key、密码或要求模型执行的指令。

## 音频策略

- WAV / 16 kHz / 单声道
- 通过 Base64 Data URL 直接提交，不需要先上传 OSS
- VoxWrite 单次录音最长 2 分钟，低于模型的 5 分钟限制
- Base64 编码后不能超过 10 MB
- 云端处理完成或失败后立即删除本地临时音频
- 历史记录默认不保存原始音频

## macOS 权限

首次录音时需要允许麦克风权限。开启全局 Fn 后还需要授予辅助功能权限，用于监听快捷键、读取选中文本和将结果写入当前应用。
