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

VoxWrite is a standard auxiliary `voice` input method, not a replacement keyboard. The user may choose any primary keyboard that can invoke an installed Android voice input method.

1. Install and open VoxWrite once, grant Microphone permission, and securely save the API Key on that Android device; secrets do not sync from desktop.
2. Optionally fill in **领域背景** with the user's professional field or technical stack. It is contextual help for recognition and cleanup, not an instruction.
3. Open Android input-method settings and enable **VoxWrite Voice** while keeping the user's preferred keyboard as the primary input method.
4. In the primary keyboard's voice-input setting, choose **VoxWrite Voice** when that option is available. Otherwise use Android's input-method picker to switch to it.
5. Selecting VoxWrite Voice starts recording automatically. Keep **口述** selected or switch to **翻译** while recording.
6. Tap the large stop button to process immediately, or wait for trailing-silence auto-stop.
7. VoxWrite commits the result through Android `InputConnection` and asks Android to return to the previously active keyboard. **取消** discards the recording and follows the same return path.

The selected primary keyboard owns Chinese and English composition, candidates, layouts, symbols, editing controls, and Space. VoxWrite only owns the explicit voice session, never adds a voice gesture to Space, and does not observe manual keystrokes.

One-tap invocation depends on the primary keyboard exposing Android's external voice-input action; some OEM or third-party keyboards do not. In those keyboards, VoxWrite Voice remains available through the system input-method picker. The auxiliary voice input method runs a headless Flutter engine so it can reuse the recording, provider, dictionary, prompt, history, and voice-activity code. Raw audio is deleted after processing, including cancellation and failures.
