import ApplicationServices
import Cocoa
import CoreGraphics
import Foundation
import os.log

final class TextDestinationBridge {
  private var capturedElement: AXUIElement?
  private var capturedProcessIdentifier: pid_t?
  private var capturedBundleIdentifier: String?

  func captureTarget() -> Bool {
    guard GlobalShortcutMonitor.accessibilityTrusted(prompt: false),
          let frontmost = NSWorkspace.shared.frontmostApplication else {
      clearTarget()
      return false
    }

    let processIdentifier = frontmost.processIdentifier
    let applicationElement = AXUIElementCreateApplication(processIdentifier)
    let candidate = Self.focusedElement(of: applicationElement)
      ?? Self.focusedElement(of: AXUIElementCreateSystemWide())
    var focused: AXUIElement?
    if let candidate {
      var elementProcessIdentifier: pid_t = 0
      if AXUIElementGetPid(candidate, &elementProcessIdentifier) == .success,
         elementProcessIdentifier == processIdentifier {
        focused = candidate
      }
    }

    // Pasting only requires the target process. Keep the AX element when an
    // app exposes one so Ask mode can still read a selection, but do not reject
    // custom inputs such as WeChat when they hide their focused element.
    capturedElement = focused
    capturedProcessIdentifier = processIdentifier
    capturedBundleIdentifier = frontmost.bundleIdentifier
    os_log(
      "captured target pid=%{public}d bundle=%{public}@ element=%{public}@",
      log: shortcutLog,
      type: .info,
      processIdentifier,
      frontmost.bundleIdentifier ?? "unknown",
      (focused != nil).description
    )
    return true
  }

  func readSelection() -> String? {
    guard GlobalShortcutMonitor.accessibilityTrusted(prompt: false),
          let target = validCapturedElement() ?? Self.focusedElement() else {
      return nil
    }

    var value: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(
      target,
      kAXSelectedTextAttribute as CFString,
      &value
    )
    guard error == .success else { return nil }
    return value as? String
  }

  func insert(_ text: String, completion: @escaping (Bool) -> Void) {
    guard !text.isEmpty else {
      clearTarget()
      completion(true)
      return
    }

    guard let processIdentifier = capturedProcessIdentifier,
          let application = NSRunningApplication(
            processIdentifier: processIdentifier
          ) else {
      os_log("insert failed: captured application exited", log: shortcutLog, type: .error)
      clearTarget()
      completion(false)
      return
    }

    let delay: TimeInterval
    if application.isActive {
      delay = 0.05
    } else {
      application.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
      delay = 0.35
    }

    os_log(
      "pasting once to pid=%{public}d bundle=%{public}@ active=%{public}@",
      log: shortcutLog,
      type: .info,
      processIdentifier,
      capturedBundleIdentifier ?? "unknown",
      application.isActive.description
    )

    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
      guard let self else {
        completion(false)
        return
      }
      let inserted = self.pasteWithClipboardRestoration(text)
      os_log(
        "paste event posted=%{public}@",
        log: shortcutLog,
        type: inserted ? .info : .error,
        inserted.description
      )
      self.clearTarget()
      completion(inserted)
    }
  }

  func clearTarget() {
    capturedElement = nil
    capturedProcessIdentifier = nil
    capturedBundleIdentifier = nil
  }

  private func validCapturedElement() -> AXUIElement? {
    guard let capturedElement,
          let capturedProcessIdentifier else { return nil }
    var currentProcessIdentifier: pid_t = 0
    guard AXUIElementGetPid(
      capturedElement,
      &currentProcessIdentifier
    ) == .success,
      currentProcessIdentifier == capturedProcessIdentifier else {
      return nil
    }
    return capturedElement
  }

  private static func focusedElement() -> AXUIElement? {
    if let frontmost = NSWorkspace.shared.frontmostApplication {
      let application = AXUIElementCreateApplication(
        frontmost.processIdentifier
      )
      if let focused = focusedElement(of: application) { return focused }
    }
    return focusedElement(of: AXUIElementCreateSystemWide())
  }

  private static func focusedElement(of owner: AXUIElement) -> AXUIElement? {
    var value: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(
      owner,
      kAXFocusedUIElementAttribute as CFString,
      &value
    )
    guard error == .success, let value else { return nil }
    return (value as! AXUIElement)
  }

  private func pasteWithClipboardRestoration(_ text: String) -> Bool {
    let pasteboard = NSPasteboard.general
    let snapshot = pasteboard.pasteboardItems?.map { item in
      item.types.reduce(into: [NSPasteboard.PasteboardType: Data]()) {
        result, type in
        if let data = item.data(forType: type) { result[type] = data }
      }
    } ?? []

    pasteboard.clearContents()
    guard pasteboard.setString(text, forType: .string) else { return false }

    guard let source = CGEventSource(stateID: .combinedSessionState),
          let keyDown = CGEvent(
            keyboardEventSource: source,
            virtualKey: 9,
            keyDown: true
          ),
          let keyUp = CGEvent(
            keyboardEventSource: source,
            virtualKey: 9,
            keyDown: false
          ) else {
      restorePasteboard(snapshot)
      return false
    }

    keyDown.flags = .maskCommand
    keyUp.flags = .maskCommand
    keyDown.post(tap: .cghidEventTap)
    keyUp.post(tap: .cghidEventTap)

    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
      self.restorePasteboard(snapshot)
    }
    return true
  }

  private func restorePasteboard(
    _ snapshot: [[NSPasteboard.PasteboardType: Data]]
  ) {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    let items = snapshot.map { values in
      let item = NSPasteboardItem()
      for (type, data) in values { item.setData(data, forType: type) }
      return item
    }
    if !items.isEmpty { pasteboard.writeObjects(items) }
  }
}
