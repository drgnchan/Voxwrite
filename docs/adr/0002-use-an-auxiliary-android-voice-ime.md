---
status: accepted
---

# Use a keyboard-independent auxiliary Android voice IME

Android VoxWrite is a voice-only auxiliary input method with a standard `voice` subtype. The user freely chooses the primary keyboard, which owns manual Chinese and English input, candidates, layouts, symbols, editing, and Space. VoxWrite starts recording when selected through the keyboard's external voice action or Android's input-method picker, commits or cancels the Voice Session, and asks Android to return to the previously active keyboard.

## Consequences

VoxWrite does not bundle, patch, recommend, or depend on a particular primary keyboard. One-tap voice invocation is available only when the chosen keyboard exposes Android's external voice-input action; otherwise the system input-method picker remains the compatible entry point. This preserves reliable `InputConnection` insertion without a persistent overlay or Accessibility service.
