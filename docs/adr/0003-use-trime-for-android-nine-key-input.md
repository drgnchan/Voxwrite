---
status: accepted
---

# Use Trime for Android nine-key input

Trime is the supported Android primary keyboard and VoxWrite remains a standard auxiliary `voice` input method. This replaces Fcitx5 because nine-key Chinese is a hard requirement: Trime can load a Rime nine-key schema and expose an explicit voice action, while VoxWrite stays isolated from manual keystrokes; the distributed compatibility build adds only the Android package-visibility query required for Trime to discover VoxWrite Voice.

## Consequences

The Trime compatibility APK and nine-key profile are distributed separately from VoxWrite. Trime remains GPL-3.0-or-later, the exact manifest patch and upstream source revision are recorded in `packaging/trime/`, and Space has no voice gesture.
