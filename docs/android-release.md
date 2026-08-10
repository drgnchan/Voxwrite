# Android release build

VoxWrite uses a stable personal release certificate for both local Debug and Release builds so updates do not invalidate secure storage after the one-time signing migration.

## Local signing material

The private certificate and passwords are intentionally outside source control:

- Keystore: `~/.voxwrite/signing/voxwrite-release.p12`
- Gradle properties: `android/key.properties`
- Alias: `voxwrite`

Back up both files together in a secure location. Losing the private key prevents future APKs from updating an installed release. Never commit either file.

Certificate SHA-256:

`1e53f5c583d389d7d304dbe4784abffe9d0297836e4d9ffbbfefdbccefaf9bb4`

## Build

```bash
flutter build apk --release --split-per-abi
flutter build apk --release
```

Version `0.3.25+34` keeps VoxWrite as a keyboard-independent, voice-only auxiliary input method. The user's preferred primary keyboard owns manual input; selecting VoxWrite Voice starts recording, commits or cancels the result, and asks Android to return to the previously active keyboard. It produces these signed artifacts in `dist/android/`:

- `VoxWrite-0.3.25-arm64-v8a-release.apk` — recommended for current Android phones; installed version code 2034
- `VoxWrite-0.3.25-armeabi-v7a-release.apk` — legacy 32-bit ARM; installed version code 1034
- `VoxWrite-0.3.25-x86_64-release.apk` — x86_64 emulators/devices; installed version code 4034
- `VoxWrite-0.3.25-universal-release.apk` — largest, architecture-independent installer; version code 34
- `SHA256SUMS` and `SHA256SUMS-0.3.25` — latest and version-pinned integrity hashes

Keep using the same ABI-specific package for updates. Flutter assigns ABI offsets to split APK version codes, so switching between a split APK and the universal APK is not an interchangeable update path.

The Release build enables R8 code shrinking and Android resource shrinking. Verify an APK with the newest installed Android build-tools `apksigner` before distribution.
