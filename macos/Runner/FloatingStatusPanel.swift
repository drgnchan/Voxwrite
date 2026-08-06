import AppKit

final class FloatingStatusPanel {
  private let panel: StatusPanel
  private let iconView = NSTextField(labelWithString: "")
  private let titleLabel = NSTextField(labelWithString: "")
  private let detailLabel = NSTextField(labelWithString: "")

  init() {
    panel = StatusPanel(
      contentRect: NSRect(x: 0, y: 0, width: 360, height: 68),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    panel.level = .floating
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.hidesOnDeactivate = false
    panel.ignoresMouseEvents = true
    panel.collectionBehavior = [
      .moveToActiveSpace,
      .fullScreenAuxiliary,
      .transient,
      .ignoresCycle,
    ]

    let effect = NSVisualEffectView()
    effect.material = .hudWindow
    effect.blendingMode = .behindWindow
    effect.state = .active
    effect.wantsLayer = true
    effect.layer?.cornerRadius = 20
    effect.layer?.masksToBounds = true
    effect.translatesAutoresizingMaskIntoConstraints = false

    iconView.font = .systemFont(ofSize: 22, weight: .semibold)
    iconView.textColor = .labelColor
    iconView.alignment = .center
    iconView.translatesAutoresizingMaskIntoConstraints = false

    titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
    titleLabel.textColor = .labelColor
    titleLabel.lineBreakMode = .byTruncatingTail
    titleLabel.translatesAutoresizingMaskIntoConstraints = false

    detailLabel.font = .systemFont(ofSize: 12, weight: .regular)
    detailLabel.textColor = .secondaryLabelColor
    detailLabel.lineBreakMode = .byTruncatingTail
    detailLabel.translatesAutoresizingMaskIntoConstraints = false

    guard let contentView = panel.contentView else { return }
    contentView.addSubview(effect)
    effect.addSubview(iconView)
    effect.addSubview(titleLabel)
    effect.addSubview(detailLabel)

    NSLayoutConstraint.activate([
      effect.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      effect.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      effect.topAnchor.constraint(equalTo: contentView.topAnchor),
      effect.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
      iconView.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 20),
      iconView.centerYAnchor.constraint(equalTo: effect.centerYAnchor),
      iconView.widthAnchor.constraint(equalToConstant: 28),
      iconView.heightAnchor.constraint(equalToConstant: 28),
      titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 14),
      titleLabel.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -18),
      titleLabel.topAnchor.constraint(equalTo: effect.topAnchor, constant: 14),
      detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
      detailLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
      detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3),
    ])
  }

  func show(title: String, detail: String, kind: String) {
    titleLabel.stringValue = title
    detailLabel.stringValue = detail
    iconView.stringValue = symbolName(for: kind)
    iconView.setAccessibilityLabel(title)
    // A background app's panel otherwise remains on the Space where the app
    // window was created. Re-apply this behavior before every presentation so
    // the status panel follows the currently active application and Space.
    panel.collectionBehavior = [
      .moveToActiveSpace,
      .fullScreenAuxiliary,
      .transient,
      .ignoresCycle,
    ]
    positionOnActiveScreen()
    panel.orderFrontRegardless()
  }

  func hide() {
    panel.orderOut(nil)
  }

  private func symbolName(for kind: String) -> String {
    switch kind {
    case "preview": return "⌨"
    case "recording": return "●"
    case "processing": return "✦"
    case "completed": return "✓"
    case "failed": return "!"
    default: return "●"
    }
  }

  private func positionOnActiveScreen() {
    let mouse = NSEvent.mouseLocation
    let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
      ?? NSScreen.main
    guard let visibleFrame = screen?.visibleFrame else { return }
    let frame = panel.frame
    panel.setFrameOrigin(
      NSPoint(
        x: visibleFrame.midX - frame.width / 2,
        y: visibleFrame.minY + 44
      )
    )
  }
}

private final class StatusPanel: NSPanel {
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}
