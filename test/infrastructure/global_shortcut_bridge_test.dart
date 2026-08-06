import 'package:flutter_test/flutter_test.dart';
import 'package:voxwrite/src/infrastructure/platform/global_shortcut_bridge.dart';

void main() {
  group('GlobalShortcutEvent', () {
    test('maps a suppressed Fn chord without starting dictation', () {
      final event = GlobalShortcutEvent.fromMap(const {
        'type': 'suppressShortcut',
      });

      expect(event.type, GlobalShortcutEventType.suppressShortcut);
    });

    test('maps Escape to session cancellation', () {
      final event = GlobalShortcutEvent.fromMap(const {'type': 'cancel'});

      expect(event.type, GlobalShortcutEventType.cancel);
    });
  });
}
