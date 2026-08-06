# VoxWrite

VoxWrite is a personal, cross-platform voice writing assistant for macOS, Windows, and Android. It independently reproduces the workflow of speaking into any application, while using original branding and UI.

## Target workflow

- **macOS Fn / Windows F8** — Dictation: clean spoken thoughts into usable text
- **macOS Fn + Left Shift / Windows Shift + F8** — Translation
- **macOS Fn + Space / Windows Ctrl + F8** — Ask, summarize, or rewrite selected text
- Android system input method with native mode controls
- Local history and personal dictionary
- Alibaba Cloud Model Studio first, with Doubao and custom providers behind adapters

See [`CONTEXT.md`](./CONTEXT.md) for domain terminology and [`research/typeless/FEATURE_MAP.md`](./research/typeless/FEATURE_MAP.md) for the observed behavior map.

## Platforms

| Platform | System-wide input plan |
| --- | --- |
| macOS | Swift event tap + captured-target clipboard insertion |
| Windows | Native low-level F8 shortcut + captured-window clipboard insertion |
| Android | Kotlin input method service backed by a headless Flutter engine |

There is intentionally no iOS target.

## Current status

Implemented:

- Flutter project for macOS, Windows, and Android
- Original responsive desktop/mobile UI
- Dictation, Translation, and Ask session state machine
- Prompt construction for cleanup, translation, and selected-text editing
- WAV 16 kHz mono microphone recording with temporary-file cleanup
- Alibaba `qwen3-asr-flash` Base64 audio recognition
- OpenAI-compatible writing provider for Qwen/Doubao-compatible endpoints
- End-to-end ASR → writing transform → result workflow
- API key storage through the platform secure store
- macOS native Fn/Fn+Shift/Fn+Space event bridge, enabled by default, with Esc cancellation and suppression of Fn+F-key/media-key false triggers
- Non-activating floating status panel that follows the active macOS Space
- Captured-target text insertion for VS Code, WeChat, TickTick, and similar apps
- Voice activity detection: trailing-silence stop, no-speech rejection, and 2-minute limit
- Persistent local history (text only), personal dictionary, provider settings, and translation target
- Source-language-preserving Dictation prompts and configurable Translation output
- macOS menu-bar lifecycle, window reopen, and optional launch at login
- Windows native F8/Shift+F8/Ctrl+F8 bridge and captured-window paste path
- Android input method service with Dictation, Translation, and Ask controls
- Built-in Android Voice, offline Pinyin, and English keyboard modes with QWERTY, long-sentence Pinyin segmentation, locally learned candidate ranking, case switching, and symbol layouts
- Android real-time waveform, duration, processing state, configured Provider reuse, and IME history persistence
- Signed, shrunk Android Release APKs with adaptive VoxWrite launcher icons, OEM-safe navigation insets, flat tonal editing keys, and guarded swipe-up clearing, verified on Xiaomi and OPPO devices
- Stale-session protection so cancelled cloud requests cannot insert text
- Domain, prompt, VAD, history, ASR parser, and widget tests

See [`docs/alibaba-cloud-setup.md`](./docs/alibaba-cloud-setup.md) for Provider configuration, [`docs/platform-integration.md`](./docs/platform-integration.md) for platform setup, and [`docs/android-release.md`](./docs/android-release.md) for signed Android builds.

Next milestone:

1. Build and run the Windows native bridge on a Windows machine
2. Tune Android VAD thresholds against more rooms, voices, and microphones
3. Add an explicit Android update/rollback workflow around the signed Release APK
4. Dogfood longer-form Android dictation in daily messaging and note-taking

## Run

```bash
flutter pub get
flutter run -d macos
```

## Verify

```bash
flutter analyze
flutter test
flutter build macos --debug
flutter build apk --debug
```

Runtime screenshots are stored in [`artifacts/screenshots/`](./artifacts/screenshots/).
