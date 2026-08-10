# Platform integration

## macOS

- Shortcuts: `Fn`, `Fn + Left Shift`, `Fn + Space`.
- Press `Esc` during shortcut preview, recording, or cloud processing to cancel without inserting text. VoxWrite consumes that Escape key only while a voice session is active; idle Escape remains available to the foreground app.
- Fn combined with F-keys, media keys, arrows, or other non-mode keys is excluded from voice activation, so system controls such as `Fn + F12` remain unaffected.
- Required permissions: Accessibility, Input Monitoring, and Microphone.
- The menu-bar item keeps VoxWrite available after the main window closes.
- Launch at login is available from Settings on macOS 13 or later.

## Windows

Windows does not expose the hardware `Fn` key to applications. VoxWrite uses:

- `F8`: Dictation
- `Shift + F8`: Translation
- `Ctrl + F8`: Ask

The native bridge captures the foreground window when recording starts and sends one clipboard paste when processing completes. Build and runtime verification must be performed on a Windows host.

## Android

VoxWrite is an auxiliary voice input method, not a replacement keyboard. The supported primary keyboard is the Trime compatibility build plus the VoxWrite nine-key Rime profile in [`packaging/trime/`](../packaging/trime/).

1. Install `Trime-3.3.11-arm64-v8a-VoxWrite-release.apk` and VoxWrite Voice. If official Trime is already installed, back up its Rime data and uninstall it first because the compatibility APK uses a different signing certificate.
2. Copy `default.custom.yaml`, `voxwrite_jiugong.schema.yaml`, and `voxwrite.trime.yaml` into `/sdcard/rime/`.
3. Open Trime, grant **Manage all files** access, enable Trime, and make it the primary input method.
4. In Trime, tap **部署**, then choose **键盘样式 → 选取主题 → VoxWrite 九键**.
5. Open **常规 → 首选语音输入法** and choose **VoxWrite Voice**. If necessary, select the **VoxWrite 九键拼音** schema.
6. Open VoxWrite once, grant Microphone permission, and securely save the API Key on that Android device; secrets do not sync from desktop.
7. Optionally fill in **领域背景** with the user's professional field or technical stack. It is contextual help for recognition and cleanup, not an instruction.
8. Tap the microphone in the Trime toolbar. VoxWrite opens and starts recording automatically.
9. Keep **口述** selected or switch to **翻译** while recording. Tap the large stop button to process immediately, or wait for trailing-silence auto-stop.
10. VoxWrite commits the result through Android `InputConnection` and returns to Trime. **取消** discards the recording and also returns to Trime.

Trime owns nine-key Chinese, 26-key English, candidates, symbols, editing controls, and Space. VoxWrite only owns the explicit voice session, never adds a voice gesture to Space, and does not observe manual keystrokes.

The Trime compatibility build changes only Android package visibility so Trime can discover the separately installed `voice` subtype; details, upstream source, license, and the exact source patch are in [`packaging/trime/README.md`](../packaging/trime/README.md). The auxiliary voice input method runs a headless Flutter engine so it can reuse the recording, provider, dictionary, prompt, history, and voice-activity code. Raw audio is deleted after processing, including cancellation and failures.
