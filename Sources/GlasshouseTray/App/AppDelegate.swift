import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let settings = Settings.shared
    private let audioRoute = AudioRoute()
    private let keyTap = MediaKeyTap()
    private let volume = VolumeController()
    private let hud = VolumeHUD()
    private var tvName = "TV"
    private var permissionPoll: Timer?
    private var promptedForPermission = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "tv", accessibilityDescription: "Glasshouse Tray")
        statusItem.button?.image?.isTemplate = true

        let menu = NSMenu()
        menu.addItem(withTitle: "Quit Glasshouse Tray", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu

        volume.client = settings.makeClient()
        volume.onDisplay = { [weak self] level, muted in
            guard let self else { return }
            self.hud.show(level: level, muted: muted, name: self.tvName)
        }
        volume.onError = { [weak self] error in
            self?.hud.show(message: "TV: \(error.localizedDescription)")
        }

        keyTap.onPress = { [weak self] press in self?.volume.handle(press) }
        audioRoute.onChange = { [weak self] in self?.updateKeyTap() }
        audioRoute.start()

        NotificationCenter.default.addObserver(forName: Settings.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.settingsChanged() }
        }

        updateKeyTap()
    }

    private func settingsChanged() {
        volume.client = settings.makeClient()
        audioRoute.refresh()
        updateKeyTap()
    }

    /// The tap only runs while the TV is the output, so the volume keys keep
    /// working normally for every other device.
    private func updateKeyTap() {
        let wanted = settings.volumeKeysEnabled && audioRoute.isTV
        guard wanted else {
            keyTap.isEnabled = false
            return
        }
        guard MediaKeyTap.hasPermission else {
            keyTap.isEnabled = false
            if !promptedForPermission {
                promptedForPermission = true
                MediaKeyTap.requestPermission()
            }
            waitForPermission()
            return
        }
        keyTap.isEnabled = true
    }

    /// Accessibility has no change notification; check every few seconds
    /// until it is granted, then stop.
    private func waitForPermission() {
        guard permissionPoll == nil else { return }
        permissionPoll = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, MediaKeyTap.hasPermission else { return }
                self.permissionPoll?.invalidate()
                self.permissionPoll = nil
                self.updateKeyTap()
            }
        }
    }
}
