import AppKit

/// A small, non-activating overlay that shows the TV's volume, standing in
/// for the system HUD (which only reflects CoreAudio devices).
@MainActor
final class VolumeHUD {
    private lazy var panel = makePanel()
    private let icon = NSImageView()
    private let title = NSTextField(labelWithString: "")
    private let bar = NSProgressIndicator()
    private var hideTask: Task<Void, Never>?

    func show(level: Int?, muted: Bool, name: String) {
        let symbol: String
        switch (muted, level) {
        case (true, _): symbol = "speaker.slash.fill"
        case (false, nil): symbol = "speaker.wave.2.fill"
        case (false, let level?): symbol = level == 0 ? "speaker.fill"
            : level < 34 ? "speaker.wave.1.fill" : level < 67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
        }
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        title.stringValue = muted ? "\(name) · Muted" : level.map { "\(name) · \($0)" } ?? name
        bar.isHidden = level == nil
        bar.doubleValue = muted ? 0 : Double(level ?? 0)
        present()
    }

    func show(message: String) {
        icon.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)
        title.stringValue = message
        bar.isHidden = true
        present()
    }

    private func present() {
        position()
        hideTask?.cancel()
        if !panel.isVisible {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
        } else if panel.alphaValue < 1 {
            // Mid fade-out: animate back so the running fade doesn't win.
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.08
                self.panel.animator().alphaValue = 1
            }
        }
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.4))
            guard !Task.isCancelled else { return }
            self?.fadeOut()
        }
    }

    private func fadeOut() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            self.panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.panel.alphaValue == 0 else { return }
                self.panel.orderOut(nil)
            }
        })
    }

    /// Top-right of the screen with the mouse, under the menu bar, where the
    /// system's own volume HUD appears.
    private func position() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: visible.maxX - size.width - 12, y: visible.maxY - size.height - 12))
    }

    private func makePanel() -> NSPanel {
        let size = NSSize(width: 240, height: 64)
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 16
        background.layer?.masksToBounds = true

        icon.symbolConfiguration = .init(pointSize: 20, weight: .medium)
        icon.contentTintColor = .labelColor
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.textColor = .labelColor
        title.lineBreakMode = .byTruncatingTail
        bar.style = .bar
        bar.isIndeterminate = false
        bar.minValue = 0
        bar.maxValue = 100
        bar.controlSize = .small

        let text = NSStackView(views: [title, bar])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 6
        let row = NSStackView(views: [icon, text])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -16),
            row.centerYAnchor.constraint(equalTo: background.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 28),
            bar.widthAnchor.constraint(equalTo: text.widthAnchor),
        ])
        panel.contentView = background
        return panel
    }
}
