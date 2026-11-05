import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let settings = Settings.shared
    private let audioRoute = AudioRoute()
    private let keyTap = MediaKeyTap()
    private let volume = VolumeController()
    private let hud = VolumeHUD()
    private lazy var menuController = MenuController(volume: volume, audioRoute: audioRoute)
    private var tvName = "TV"
    private var permissionPoll: Timer?
    private var promptedForPermission = false
    private var lastToken: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "tv", accessibilityDescription: "Glasshouse Tray")
        statusItem.button?.image?.isTemplate = true

        statusItem.menu = menuController.menu

        menuController.onStats = { [weak self] stats in self?.absorb(stats) }
        menuController.onReachabilityChange = { [weak self] reachable in
            self?.statusItem.button?.appearsDisabled = !reachable
        }
        menuController.onError = { [weak self] error in
            self?.hud.show(message: error.localizedDescription)
        }
        menuController.onOpenSettings = { SettingsPanel.present() }

        lastToken = settings.token
        let client = settings.makeClient()
        volume.client = client
        menuController.client = client
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

        // First run: ask for the TV's address once launching has finished.
        if settings.host.isEmpty {
            Task { SettingsPanel.present() }
        }
    }

    private func absorb(_ stats: Stats) {
        volume.sync(with: stats)
        if let name = stats.device?.name { tvName = name }
        if let mac = stats.mac, mac != settings.tvMAC { settings.tvMAC = mac }
    }

    private func settingsChanged() {
        let client = settings.makeClient()
        if client?.baseURL != volume.client?.baseURL || settings.token != lastToken {
            lastToken = settings.token
            volume.client = client
            menuController.client = client
        }
        audioRoute.refresh()
        updateKeyTap()
    }

    /// The tap only runs while the TV is the output, so the volume keys keep
    /// working normally for every other device.
    private func updateKeyTap() {
        let wanted = settings.volumeKeysEnabled && audioRoute.isTV && volume.client != nil
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
