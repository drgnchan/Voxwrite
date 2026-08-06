# 阿里云百炼配置

VoxWrite 当前优先接入阿里云百炼：

- 语音识别：`qwen3-asr-flash`
- 文字整理：`qwen-plus`
- 请求方式：OpenAI 兼容 `chat/completions`

## 设置项

在 VoxWrite → 设置中填写：

| 设置 | 推荐值 |
| --- | --- |
| 服务商 | 阿里云百炼 |
| Base URL | `https://dashscope.aliyuncs.com/compatible-mode/v1` |
| 文本模型 | `qwen-plus` |
| 语音识别模型 | `qwen3-asr-flash` |
| API Key | 从百炼控制台创建的 Key |

如果当前业务空间要求专属地址，请将 Base URL 改为：

```text
https://{WorkspaceId}.cn-beijing.maas.aliyuncs.com/compatible-mode/v1
```

API Key 只保存在系统安全存储中，不写入项目文件或普通偏好设置。

## 音频策略

- WAV / 16 kHz / 单声道
- 通过 Base64 Data URL 直接提交，不需要先上传 OSS
- 单次录音最长 5 分钟
- Base64 编码后不能超过 10 MB
- 云端处理完成或失败后立即删除本地临时音频
- 历史记录默认不保存原始音频

## macOS 权限

首次录音时需要允许麦克风权限。开启全局 Fn 后还需要授予辅助功能权限，用于监听快捷键、读取选中文本和将结果写入当前应用。
