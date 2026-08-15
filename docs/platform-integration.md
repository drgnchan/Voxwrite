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

## Linux

Linux uses the same shortcuts as Windows:

- `F8`: Dictation
- `Shift + F8`: Translation
- `Ctrl + F8`: Ask
- `Esc`: cancel an active Voice Session

On an **X11 session**, the native runner grabs these shortcuts, remembers the `_NET_ACTIVE_WINDOW`, reads selected text from the X11 PRIMARY selection for Ask, and sends one clipboard paste to the captured window after processing.

On a **Wayland session**, the native runner registers F8 / Shift+F8 / Ctrl+F8 through the xdg-desktop-portal **GlobalShortcuts** interface on compositors that implement it (KDE Plasma 5.27+, GNOME 48+, Hyprland). The first use shows a compositor authorization prompt; after approval the shortcuts work globally and VoxWrite raises its window so the session is visible and cancellable. Compositors without the portal (sway/wlroots, older GNOME) keep the in-app-only fallback.

Wayland security still prevents an ordinary application from identifying/focusing another client's window or injecting a paste, so after processing VoxWrite copies the result to the clipboard instead of inserting it, Ask mode cannot ground on another app's text selection, and the global `Esc` cancel is unavailable (cancel from the VoxWrite window). To get true automatic insertion on Wayland, enable the **Wayland 自动回填** setting and install the kernel-level input injector:

```bash
sudo dnf install ydotool wl-clipboard
sudo systemctl enable --now ydotool
sudo usermod -aG input $USER   # then log out and back in
```

With auto-backfill enabled VoxWrite records silently (it no longer raises its window, so the focused application keeps focus), publishes the result through `wl-copy`, and injects Ctrl+V through `ydotool key` after processing; a desktop notification reports when recording starts. If the tools are missing, it silently falls back to the clipboard. Log in with an X11 session for the complete insert workflow without the extra tool.

Build prerequisites on Debian/Ubuntu include Flutter's normal Linux desktop dependencies plus the packages used by VoxWrite and its plugins:

```bash
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev \
  libx11-dev libxtst-dev libsecret-1-dev ffmpeg pulseaudio-utils
flutter pub get
flutter build linux --release
```

Linux builds and runtime behavior must be verified on a Linux host.

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
