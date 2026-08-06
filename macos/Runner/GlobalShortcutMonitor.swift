import ApplicationServices
import CoreGraphics
import FlutterMacOS
import Foundation
import os.log

let shortcutLog = OSLog(
  subsystem: "dev.raymond.voxwrite",
  category: "GlobalShortcut"
)

final class ShortcutEventStreamHandler: NSObject, FlutterStreamHandler {
  private let monitor = GlobalShortcutMonitor()

  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    monitor.eventSink = events
    os_log("event stream subscribed", log: shortcutLog, type: .info)
    do {
      try monitor.start()
      os_log("event tap started", log: shortcutLog, type: .info)
      return nil
    } catch {
      os_log(
        "event tap failed: %{public}@",
        log: shortcutLog,
        type: .error,
        String(describing: error)
      )
      return FlutterError(
        code: "SHORTCUT_MONITOR_FAILED",
        message: "Unable to start the global shortcut monitor.",
        details: String(describing: error)
      )
    }
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    monitor.stop()
    monitor.eventSink = nil
    return nil
  }

  func setSessionActive(_ active: Bool) {
    monitor.setSessionActive(active)
  }
}

private enum GlobalShortcutMonitorError: Error {
  case permissionsMissing
  case eventTapUnavailable
  case runLoopSourceUnavailable
}

final class GlobalShortcutMonitor {
  var eventSink: FlutterEventSink?

  private var eventTap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?
  private var functionKeyDown = false
  private var shortcutSuppressed = false
  private var selectedTranslation = false
  private var selectedAsk = false
  private var sessionActive = false
  private var consumeEscapeKeyUp = false

  static func accessibilityTrusted(prompt: Bool) -> Bool {
    let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
    return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
  }

  static func inputMonitoringTrusted(prompt: Bool) -> Bool {
    if CGPreflightListenEventAccess() { return true }
    return prompt ? CGRequestListenEventAccess() : false
  }

  func start() throws {
    guard eventTap == nil else { return }
    guard Self.accessibilityTrusted(prompt: false),
          Self.inputMonitoringTrusted(prompt: false) else {
      throw GlobalShortcutMonitorError.permissionsMissing
    }

    let flagsChanged = CGEventMask(1) << CGEventType.flagsChanged.rawValue
    let keyDown = CGEventMask(1) << CGEventType.keyDown.rawValue
    let keyUp = CGEventMask(1) << CGEventType.keyUp.rawValue
    // NSEvent.systemDefined is raw CGEvent type 14, but CoreGraphics does
    // not expose a named CGEventType case for it.
    let systemDefined = CGEventMask(1) << 14
    let eventMask = flagsChanged | keyDown | keyUp | systemDefined
    let userInfo = UnsafeMutableRawPointer(
      Unmanaged.passUnretained(self).toOpaque()
    )

    guard let tap = CGEvent.tapCreate(
      tap: .cgSessionEventTap,
      place: .headInsertEventTap,
      options: .defaultTap,
      eventsOfInterest: eventMask,
      callback: Self.eventCallback,
      userInfo: userInfo
    ) else {
      throw GlobalShortcutMonitorError.eventTapUnavailable
    }

    guard let source = CFMachPortCreateRunLoopSource(nil, tap, 0) else {
      CFMachPortInvalidate(tap)
      throw GlobalShortcutMonitorError.runLoopSourceUnavailable
    }

    eventTap = tap
    runLoopSource = source
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
  }

  func stop() {
    if let eventTap {
      CGEvent.tapEnable(tap: eventTap, enable: false)
      CFMachPortInvalidate(eventTap)
    }
    if let runLoopSource {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
    }
    eventTap = nil
    runLoopSource = nil
    functionKeyDown = false
    shortcutSuppressed = false
    selectedTranslation = false
    selectedAsk = false
    sessionActive = false
    consumeEscapeKeyUp = false
  }

  func setSessionActive(_ active: Bool) {
    sessionActive = active
    os_log(
      "shortcut session active=%{public}@",
      log: shortcutLog,
      type: .info,
      active.description
    )
  }

  private static let eventCallback: CGEventTapCallBack = {
    _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let monitor = Unmanaged<GlobalShortcutMonitor>
      .fromOpaque(userInfo)
      .takeUnretainedValue()
    let shouldConsume = monitor.handle(type: type, event: event)
    return shouldConsume ? nil : Unmanaged.passUnretained(event)
  }

  private func handle(type: CGEventType, event: CGEvent) -> Bool {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
      return false
    }

    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
    let flags = event.flags

    if type == .flagsChanged {
      let functionNowDown = flags.contains(.maskSecondaryFn)
      if functionNowDown && !functionKeyDown {
        os_log("fn down", log: shortcutLog, type: .info)
        functionKeyDown = true
        shortcutSuppressed = false
        selectedTranslation = false
        selectedAsk = false
        emit(type: "fnDown")
      }

      if functionKeyDown,
         flags.contains(.maskShift),
         keyCode == 56 || keyCode == 60,
         !selectedTranslation {
        selectedTranslation = true
        emit(type: "selectTranslation")
      }

      if !functionNowDown && functionKeyDown {
        os_log("fn up", log: shortcutLog, type: .info)
        functionKeyDown = false
        if !shortcutSuppressed {
          emit(type: "fnUp")
        }
        shortcutSuppressed = false
      }
      return false
    }

    if type.rawValue == 14, functionKeyDown {
      suppressCurrentShortcut(keyCode: keyCode)
      return false
    }

    if type == .keyUp, keyCode == 53, consumeEscapeKeyUp {
      consumeEscapeKeyUp = false
      return true
    }

    guard type == .keyDown else { return false }
    let isAutoRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
    if keyCode == 53, sessionActive {
      if functionKeyDown {
        suppressCurrentShortcut(keyCode: keyCode)
      }
      consumeEscapeKeyUp = true
      if !isAutoRepeat {
        emit(type: "cancel")
      }
      return true
    }

    guard functionKeyDown else { return false }
    if keyCode == 49 {
      if !selectedAsk {
        selectedAsk = true
        emit(type: "selectAsk")
      }
      return false
    }

    suppressCurrentShortcut(keyCode: keyCode)
    return false
  }

  private func suppressCurrentShortcut(keyCode: Int64) {
    guard functionKeyDown, !shortcutSuppressed else { return }
    shortcutSuppressed = true
    os_log(
      "suppressing fn shortcut for keyCode=%{public}lld",
      log: shortcutLog,
      type: .info,
      keyCode
    )
    emit(type: "suppressShortcut")
  }

  private func emit(type: String) {
    DispatchQueue.main.async { [weak self] in
      os_log(
        "emitting %{public}@ to Flutter",
        log: shortcutLog,
        type: .info,
        type
      )
      self?.eventSink?(["type": type])
    }
  }
}
