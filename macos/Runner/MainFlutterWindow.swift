import Cocoa
import FlutterMacOS
import os.log

class MainFlutterWindow: NSWindow {
  private var shortcutStreamHandler: ShortcutEventStreamHandler?
  private var shortcutEventChannel: FlutterEventChannel?
  private var permissionMethodChannel: FlutterMethodChannel?
  private var textDestinationMethodChannel: FlutterMethodChannel?
  private var overlayMethodChannel: FlutterMethodChannel?
  private var lifecycleMethodChannel: FlutterMethodChannel?
  private let floatingStatusPanel = FloatingStatusPanel()
  private let textDestinationBridge = TextDestinationBridge()

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    configureNativeBridges(messenger: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }

  private func configureNativeBridges(messenger: FlutterBinaryMessenger) {
    let streamHandler = ShortcutEventStreamHandler()
    let eventChannel = FlutterEventChannel(
      name: "dev.raymond.voxwrite/shortcuts",
      binaryMessenger: messenger
    )
    eventChannel.setStreamHandler(streamHandler)
    shortcutStreamHandler = streamHandler
    shortcutEventChannel = eventChannel

    let methodChannel = FlutterMethodChannel(
      name: "dev.raymond.voxwrite/permissions",
      binaryMessenger: messenger
    )
    methodChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "hasAccessibilityPermission":
        result(GlobalShortcutMonitor.accessibilityTrusted(prompt: false))
      case "requestAccessibilityPermission":
        let trusted = GlobalShortcutMonitor.accessibilityTrusted(prompt: true)
        os_log(
          "accessibility trusted=%{public}@",
          log: shortcutLog,
          type: .info,
          trusted.description
        )
        result(trusted)
      case "hasInputMonitoringPermission":
        result(GlobalShortcutMonitor.inputMonitoringTrusted(prompt: false))
      case "requestInputMonitoringPermission":
        let trusted = GlobalShortcutMonitor.inputMonitoringTrusted(prompt: true)
        os_log(
          "input monitoring trusted=%{public}@",
          log: shortcutLog,
          type: .info,
          trusted.description
        )
        result(trusted)
      case "setShortcutSessionActive":
        guard let arguments = call.arguments as? [String: Any],
              let active = arguments["active"] as? Bool else {
          result(
            FlutterError(
              code: "INVALID_SHORTCUT_SESSION",
              message: "setShortcutSessionActive requires an active argument.",
              details: nil
            )
          )
          return
        }
        streamHandler.setSessionActive(active)
        result(nil)
      case "openAccessibilitySettings":
        if let url = URL(
          string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) {
          NSWorkspace.shared.open(url)
        }
        result(nil)
      case "openInputMonitoringSettings":
        if let url = URL(
          string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        ) {
          NSWorkspace.shared.open(url)
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    permissionMethodChannel = methodChannel

    let lifecycleChannel = FlutterMethodChannel(
      name: "dev.raymond.voxwrite/lifecycle",
      binaryMessenger: messenger
    )
    lifecycleChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "isLaunchAtLoginSupported":
        result(LaunchAtLoginBridge.isSupported)
      case "isLaunchAtLoginEnabled":
        result(LaunchAtLoginBridge.isEnabled)
      case "setLaunchAtLogin":
        guard let arguments = call.arguments as? [String: Any],
              let enabled = arguments["enabled"] as? Bool else {
          result(
            FlutterError(
              code: "INVALID_LAUNCH_AT_LOGIN",
              message: "setLaunchAtLogin requires an enabled argument.",
              details: nil
            )
          )
          return
        }
        do {
          try LaunchAtLoginBridge.setEnabled(enabled)
          result(LaunchAtLoginBridge.isEnabled)
        } catch {
          result(
            FlutterError(
              code: "LAUNCH_AT_LOGIN_FAILED",
              message: "Unable to update launch at login.",
              details: String(describing: error)
            )
          )
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    lifecycleMethodChannel = lifecycleChannel

    let textChannel = FlutterMethodChannel(
      name: "dev.raymond.voxwrite/text_destination",
      binaryMessenger: messenger
    )
    textChannel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(
          FlutterError(
            code: "WINDOW_UNAVAILABLE",
            message: "The VoxWrite window is unavailable.",
            details: nil
          )
        )
        return
      }
      switch call.method {
      case "captureTarget":
        result(textDestinationBridge.captureTarget())
      case "readSelection":
        result(textDestinationBridge.readSelection())
      case "insertText":
        guard let arguments = call.arguments as? [String: Any],
              let text = arguments["text"] as? String else {
          result(
            FlutterError(
              code: "INVALID_TEXT",
              message: "insertText requires a text argument.",
              details: nil
            )
          )
          return
        }
        textDestinationBridge.insert(text) { inserted in
          result(inserted)
        }
      case "clearTarget":
        textDestinationBridge.clearTarget()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    textDestinationMethodChannel = textChannel

    let overlayChannel = FlutterMethodChannel(
      name: "dev.raymond.voxwrite/overlay",
      binaryMessenger: messenger
    )
    overlayChannel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "show":
        guard let arguments = call.arguments as? [String: Any],
              let title = arguments["title"] as? String,
              let detail = arguments["detail"] as? String,
              let kind = arguments["kind"] as? String else {
          result(
            FlutterError(
              code: "INVALID_OVERLAY",
              message: "show requires title, detail, and kind.",
              details: nil
            )
          )
          return
        }
        self?.floatingStatusPanel.show(
          title: title,
          detail: detail,
          kind: kind
        )
        result(nil)
      case "hide":
        self?.floatingStatusPanel.hide()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    overlayMethodChannel = overlayChannel
  }
}
