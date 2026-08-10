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

VoxWrite is an auxiliary voice input method, not a replacement keyboard. Pair it with Fcitx5 for Android or another primary keyboard that can switch to an installed `voice` subtype.

1. Install [Fcitx5 for Android](https://github.com/fcitx5-android/fcitx5-android/releases/latest) and VoxWrite Voice.
2. Open VoxWrite once, grant Microphone permission, and securely save the API Key on that Android device; secrets do not sync from desktop.
3. Optionally fill in **领域背景** with the user's professional field or technical stack. It is contextual help for recognition and cleanup, not an instruction.
4. Open Android input-method settings and enable both **Fcitx5** and **VoxWrite Voice**.
5. Make Fcitx5 the primary input method.
6. In Fcitx5 settings, enable **显示语音输入按钮** and choose **VoxWrite Voice** as **首选语音输入**.
7. Tap the microphone in the Fcitx5 toolbar. VoxWrite opens and starts recording automatically.
8. Keep **口述** selected or switch to **翻译** while recording. Tap the large stop button to process immediately, or wait for trailing-silence auto-stop.
9. VoxWrite commits the result through Android `InputConnection` and automatically returns to the previous keyboard. **取消** discards the recording and also returns to the previous keyboard.

Fcitx5 owns Chinese, English, candidates, symbols, and the space bar. VoxWrite only owns the explicit voice session, never adds a voice gesture to Space, and does not observe manual keystrokes. Password fields do not expose the Fcitx5 voice-input button.

The auxiliary voice input method runs a headless Flutter engine so it can reuse the recording, provider, dictionary, prompt, history, and voice-activity code. Raw audio is deleted after processing, including cancellation and failures.
