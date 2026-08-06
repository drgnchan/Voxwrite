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

1. Open VoxWrite once and grant Microphone permission.
2. Save the API Key in VoxWrite on that Android device; secrets do not sync from desktop.
3. In Settings, choose **启用输入法** and enable **VoxWrite 语音输入**.
4. Choose **选择 VoxWrite** to make it the active input method.
5. Use the top switcher to choose **语音**, **拼音**, or **EN**.
6. In Voice mode, select Dictation, Translation, or Ask and start speaking.
7. In Pinyin mode, type full Pinyin or a continuous multi-word sentence and tap a candidate or press Space to choose the first candidate. Explicit candidate choices are learned locally; Backspace edits the active composition before deleting committed text.
8. In English mode, use Shift for one uppercase letter, double-tap Shift for Caps Lock, and use `?123` for numbers and symbols.
9. In Voice mode, tap Delete to remove one character, or hold Delete until the haptic cue and swipe upward to clear the entire current field. Holding and releasing without the upward swipe cancels clearing.

The Pinyin lexicon is fully offline and generated from the MIT-licensed jieba and pypinyin projects; its notice is packaged under `assets/licenses/`. Keyboard mode and up to 512 candidate-selection preferences are remembered locally. Neither keystrokes nor learned ranking data are sent to a Pinyin service.

The input method runs a headless Flutter engine so it can reuse the same recording, provider, dictionary, prompt, and voice-activity code. Results are committed through Android `InputConnection`; raw audio is deleted after processing. Its bottom padding follows Android navigation-bar, tappable-element, and system-gesture insets to avoid OEM controls overlaying the editing row.
