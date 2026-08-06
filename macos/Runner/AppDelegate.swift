import Cocoa
import FlutterMacOS
import ServiceManagement

@main
class AppDelegate: FlutterAppDelegate {
  private var statusItem: NSStatusItem?

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    configureStatusItem()
    DispatchQueue.main.async { [weak self] in
      self?.showMainWindow()
    }
  }

  override func applicationShouldTerminateAfterLastWindowClosed(
    _ sender: NSApplication
  ) -> Bool {
    return false
  }

  override func applicationShouldHandleReopen(
    _ sender: NSApplication,
    hasVisibleWindows flag: Bool
  ) -> Bool {
    showMainWindow()
    return true
  }

  override func applicationSupportsSecureRestorableState(
    _ app: NSApplication
  ) -> Bool {
    return true
  }

  @objc private func showMainWindow() {
    NSApp.activate(ignoringOtherApps: true)
    mainFlutterWindow?.makeKeyAndOrderFront(nil)
  }

  @objc private func quitApplication() {
    NSApp.terminate(nil)
  }

  private func configureStatusItem() {
    let item = NSStatusBar.system.statusItem(
      withLength: NSStatusItem.squareLength
    )
    if let button = item.button {
      button.title = "◉"
      button.toolTip = "VoxWrite"
    }

    let menu = NSMenu()
    let openItem = NSMenuItem(
      title: "打开 VoxWrite",
      action: #selector(showMainWindow),
      keyEquivalent: ""
    )
    openItem.target = self
    menu.addItem(openItem)
    menu.addItem(.separator())
    let quitItem = NSMenuItem(
      title: "退出 VoxWrite",
      action: #selector(quitApplication),
      keyEquivalent: "q"
    )
    quitItem.target = self
    menu.addItem(quitItem)
    item.menu = menu
    statusItem = item
  }
}

enum LaunchAtLoginBridge {
  static var isSupported: Bool {
    if #available(macOS 13.0, *) { return true }
    return false
  }

  static var isEnabled: Bool {
    if #available(macOS 13.0, *) {
      return SMAppService.mainApp.status == .enabled
    }
    return false
  }

  static func setEnabled(_ enabled: Bool) throws {
    guard #available(macOS 13.0, *) else { return }
    if enabled {
      if SMAppService.mainApp.status != .enabled {
        try SMAppService.mainApp.register()
      }
    } else if SMAppService.mainApp.status == .enabled {
      try SMAppService.mainApp.unregister()
    }
  }
}
