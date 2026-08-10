# Trime companion keyboard

VoxWrite uses Trime as its primary Android keyboard. These files add a compact nine-key Simplified Chinese layout backed by Trime's bundled Luna Pinyin dictionary, plus a visible microphone action that switches to the `VoxWrite Voice` auxiliary input method.

## Compatibility build

Use `Trime-3.3.11-arm64-v8a-VoxWrite-release.apk`, not the unmodified Trime 3.3.11 APK. Android package visibility prevents the unmodified build from discovering a separately installed user voice input method. The compatibility build is the official Trime 3.3.11 arm64 APK with only the manifest query in `0001-discover-installed-input-methods.patch` added, then re-signed with the VoxWrite release certificate.

Upstream:

- Project: <https://github.com/osfans/trime>
- Version: `3.3.11`
- Commit: `e4e67cdb9ebb1c59edbeed508bdbd572a3021beb`
- License: GPL-3.0-or-later
- Original APK SHA-256: `59bae89d78186cb894ac8d072eed01044cb55322c3ed180e96423d860de53bb1`
- Compatibility APK SHA-256: `a4366de052399e58bdfeee3a4e579cb4a805348fc5020bc825e2a75991bb81f2`
- Nine-key profile ZIP SHA-256: `38090410f8fe2c8ffdf29115db4aa075f0e74c309a9238be8e99dfa60f3ab066`
- Compatibility signing-certificate SHA-256: `1e53f5c583d389d7d304dbe4784abffe9d0297836e4d9ffbbfefdbccefaf9bb4`

Because the compatibility APK has a different signature, uninstall an official Trime installation before installing it. Back up existing Rime user data first. The original app source remains GPL-3.0-or-later; the exact compatibility change is provided as a source patch in this directory.

## Install the nine-key profile

1. Install VoxWrite and the Trime compatibility APK.
2. Copy these files into the phone's `/sdcard/rime/` directory:
   - `default.custom.yaml`
   - `voxwrite_jiugong.schema.yaml`
   - `voxwrite.trime.yaml`
3. Open Trime and grant **Manage all files** access.
4. Enable Trime and `VoxWrite Voice` in Android's input-method settings, then make Trime the primary input method.
5. In Trime, tap **部署**.
6. Open **键盘样式 → 选取主题** and choose **VoxWrite 九键**.
7. Open **常规 → 首选语音输入法** and choose **VoxWrite Voice**.
8. If necessary, use Trime's schema menu and select **VoxWrite 九键拼音**.

The toolbar microphone starts VoxWrite immediately. Recording completion, cancellation, and **返回键盘** return to Trime. Space only inserts/selects Space and supports cursor sliding; it has no voice gesture.

## Rebuild the compatibility APK

The shipped binary was reproduced from the official APK with Apktool 3.0.3:

1. Decode the official Trime 3.3.11 arm64 APK.
2. Apply `0001-discover-installed-input-methods.patch` to `AndroidManifest.xml`.
3. Rebuild with Apktool.
4. Run `zipalign`.
5. Sign with the VoxWrite Android release key using `apksigner`.

No Trime Kotlin, Java, native code, or Rime engine code is modified.
