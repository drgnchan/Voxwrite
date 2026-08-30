# VoxWrite

[![CI](https://github.com/drgnchan/Voxwrite/actions/workflows/ci.yml/badge.svg)](https://github.com/drgnchan/Voxwrite/actions/workflows/ci.yml)
[![License: Apache-2.0](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)

Say it out loud, and the words write themselves.

VoxWrite is a cross-platform voice writing assistant for macOS, Windows, Linux, and Android. Speak into the microphone and VoxWrite transcribes, cleans up, and inserts natural text right into the app you're using — chat, email, notes, or documents.

> [中文文档](./README.md)

## Three modes

| Mode | What it does |
| --- | --- |
| **Dictation** | Keeps your meaning, removes filler, and adds punctuation and structure to turn speech into usable text |
| **Translation** | Cleans up the wording first, then produces natural text in the target language (choose it in Settings) |
| **Ask & Rewrite** | Ask questions about, polish, summarize, or rewrite the selected text |

## Supported platforms & how to trigger

| Platform | Global shortcut | Where the result goes |
| --- | --- | --- |
| macOS | `Fn` Dictation · `Fn + Shift` Translation · `Fn + Space` Ask & Rewrite | Pasted automatically into the active input field |
| Windows | `F8` Dictation · `Shift + F8` Translation · `Ctrl + F8` Ask & Rewrite | Pasted automatically into the active input field |
| Linux | `F8` Dictation · `Shift + F8` Translation · `Ctrl + F8` Ask & Rewrite | X11: auto-inserted; Wayland: copied to clipboard by default, optional auto-insert |
| Android | Used as a companion voice input method, one switch away from any keyboard | Text is committed to the active input field, then your previous keyboard is restored |

Android currently supports Dictation and Translation. There is intentionally no iOS version.

## Getting started

### 1. Get an API key

VoxWrite does speech recognition and text processing in the cloud using **your own** cloud account:

- **Speech recognition**: uses Alibaba Cloud Model Studio (DashScope) Qwen-Audio. You need a DashScope account and an API key.
- **Text processing**: uses an OpenAI-compatible endpoint — choose between Alibaba Cloud (Bailian), Doubao, DeepSeek, or a custom compatible endpoint, each with its own API key.

> Usage is billed by the cloud providers themselves; VoxWrite is free.

### 2. Install

Install the package for your platform and complete any system permission prompts on first launch (see per-platform notes below).

### 3. Configure

Open the **Settings** page in VoxWrite:

1. **Speech recognition**: enter the DashScope Base URL and recognition model (default `qwen-audio-3.0-asr-flash`), then securely save your API key.
2. **Text model**: pick a provider (Alibaba Cloud / Doubao / DeepSeek / Custom), enter the Base URL and model name, then securely save your API key.
3. Optionally fill in your **Domain Background** and choose a **Translation target language**, and you're ready to go.

API keys are stored in the system secure store — never written to disk in plain text.

## Usage

### Desktop (macOS / Windows / Linux)

- Press the shortcut to start recording; press it again (or tap **Stop**) to finish. With **Auto-stop on silence** enabled, it stops on its own (about 1.4 s of silence; recording is capped at 2 minutes).
- Tap **Cancel** in the recording panel to discard the recording, or press `Esc` while the VoxWrite window is focused. Linux also provides global `Ctrl + Shift + F8` (and global `Esc` on X11), so cancellation remains available when Wayland auto-backfill keeps the window hidden.
- While holding the shortcut before recording starts, hold `Shift` or `Space` to switch modes (macOS: `Fn + Shift` / `Fn + Space`).
- **macOS**: grant **Accessibility** and **Input Monitoring** permissions under System Settings → Privacy & Security on first use (one-tap buttons are provided in Settings). Closing the window keeps it available from the menu bar; optional launch at login.
- **Windows**: system-wide F8 shortcuts, no extra permissions needed.
- **Linux**: global F8 with auto-insert on X11. On Wayland, enable "Wayland auto-insert" in Settings (requires `ydotool`, `wl-clipboard`, and the ydotool service running); otherwise results go to the clipboard for you to paste. Closing the window keeps VoxWrite in the system tray so shortcuts keep working.

### Android

VoxWrite is a standalone companion voice input method that works alongside your primary keyboard (Sogou, Baidu, Gboard, Fcitx5, etc.):

1. Tap "Enable VoxWrite Voice" in Settings and enable it in the system input-method list.
2. While typing, switch to **VoxWrite Voice** from the input-method switcher (or long-press the spacebar).
3. Recording starts automatically; it stops and commits the text on its own, then returns to your previous keyboard.

The keyboard you pick in "Choose primary input method" remains your default for manual typing.

## Settings at a glance

| Setting | Description |
| --- | --- |
| Speech recognition / Text model | Cloud account, endpoint, and model configuration |
| Domain background | Describe your field or tech stack to improve recognition and cleanup of specialized terms (used as background context only — it's not an instruction) |
| Personal dictionary | Custom entries are sent as live hotwords so names and product terms are spelled exactly right |
| Translation target | English, Simplified Chinese, Traditional Chinese, Japanese, Korean, Spanish, French, German |
| Auto-stop on silence | Stop recording automatically after silence and start processing |
| Global shortcuts | Toggle desktop global-shortcut listening |
| Launch at login | Optional on desktop (supported on macOS) |

## Privacy

- Audio is not written to history by default; local history stores only the resulting text.
- Recording and text processing require a network connection and are sent to the cloud provider you configured.
- API keys are kept in the system secure store.
- Settings like Domain Background are stored locally and sent to your cloud provider with requests for context.

## FAQ

**Recognition is inaccurate?** Add names and product terms to the **Personal dictionary**, and fill in your **Domain Background**.

**The cleaned-up text doesn't sound like me?** Dictation preserves your source language and intent — it only removes fillers and adds punctuation and structure. If it still isn't right, try a different text model in Settings.

**Nothing is inserted on Wayland?** Enable "Wayland auto-insert" in Settings and make sure the `ydotool` service is running; otherwise results land on the clipboard and you can paste manually.

**Does it cost money?** VoxWrite itself is free; recognition and processing consume quota from your Alibaba Cloud / Doubao / DeepSeek account.

## Open source and contributing

VoxWrite is open source under the [Apache License 2.0](LICENSE). Bug reports, feature proposals, and pull requests are welcome. Before contributing, read the [contribution guide](CONTRIBUTING.md) and [Code of Conduct](CODE_OF_CONDUCT.md). Report vulnerabilities privately according to the [security policy](SECURITY.md), not through public issues.

See [CHANGELOG.md](CHANGELOG.md) for notable changes.

## Building from source (developers)

The rest of this README targets end users. If you want to build VoxWrite yourself or contribute, here's what you need.

**Prerequisites**: a stable Flutter SDK satisfying the constraints in `pubspec.yaml` and `pubspec.lock`.

```bash
flutter pub get
flutter run -d macos   # macOS
flutter run -d linux   # Linux (requires GTK3)
flutter run -d windows # Windows
flutter run -d android # Android device or emulator
```

Lint and tests:

```bash
flutter analyze
flutter test
```

Platform notes:

- **macOS**: the global Fn listener requires Accessibility and Input Monitoring permissions granted by the user in System Settings (one-tap links are provided in the in-app Settings page).
- **Linux**: depends on GTK3; native global F8 on X11, Wayland goes through xdg-desktop-portal global shortcuts with optional ydotool auto-insert.
- **Android**: Debug builds require no signing configuration. To produce a signed release, configure `keyAlias`, `keyPassword`, `storeFile`, and `storePassword` in `android/key.properties`; that file and keystores are ignored by Git. Release builds enable code and resource shrinking.
