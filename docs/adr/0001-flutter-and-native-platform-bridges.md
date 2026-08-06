# Use Flutter with native platform bridges

The product targets macOS, Windows, and Android while requiring system-level capabilities that are not portable: global keyboard events, cross-application text insertion, and an Android input method. We share presentation, domain, provider, persistence, voice-activity, and synchronization code in Flutter, while implementing those privileged capabilities in Swift, Windows native code, and Kotlin respectively. This favors one product codebase without pretending that system-wide input can be implemented by a lowest-common-denominator plugin.

Platform bindings use macOS Fn events, Windows F8 events (hardware Fn is not exposed by Windows), and an Android `InputMethodService` backed by a headless Flutter engine. Text insertion captures the destination when recording begins and performs one platform-native commit/paste after processing.
