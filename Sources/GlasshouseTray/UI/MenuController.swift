import AppKit

/// Builds the status item's menu and keeps it current while it is open.
///
/// The TV is polled only while the menu is open (and once at launch or when
/// settings change). With the menu closed the app makes no requests unless a
/// volume key is pressed.
@MainActor
final class MenuController: NSObject, NSMenuDelegate {
    let menu = NSMenu()

    var client: GlasshouseClient? {
        didSet {
            generation += 1
            refreshing = false
            stats = nil
            reachable = false
            refresh()
        }
    }

    var onStats: ((Stats) -> Void)?
    var onReachabilityChange: ((Bool) -> Void)?
    var onError: ((Error) -> Void)?
    var onOpenSettings: (() -> Void)?

    private let volume: VolumeController
    private let audioRoute: AudioRoute
    private let keyTap: MediaKeyTap
    private let settings = Settings.shared

    private(set) var stats: Stats?
    private(set) var reachable = false {
        didSet { if reachable != oldValue { onReachabilityChange?(reachable) } }
    }
    private var isOpen = false
    private var refreshing = false
    /// Bumped when the client changes, so a reply from the old TV is dropped.
    private var generation = 0
    private var pollTimer: Timer?
    private var builtStructure = ""

    // Items updated in place while the menu is open.
    private var headerItem: NSMenuItem?
    private var sliderView: VolumeSliderView?
    private var muteItem: NSMenuItem?
    private var inputMenu: NSMenu?
    private var soundMenu: NSMenu?
    private var pictureMenu: NSMenu?

    init(volume: VolumeController, audioRoute: AudioRoute, keyTap: MediaKeyTap) {
        self.volume = volume
        self.audioRoute = audioRoute
        self.keyTap = keyTap
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        guard menu === self.menu else { return }
        isOpen = true
        build()
        refresh()
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        // Menus track events in their own run loop mode.
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    func menuDidClose(_ menu: NSMenu) {
        guard menu === self.menu else { return }
        isOpen = false
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // MARK: - State

    func refresh() {
        guard let client, !refreshing else { return }
        refreshing = true
        let expected = generation
        Task {
            let stats = try? await client.stats()
            guard expected == generation else { return }
            refreshing = false
            if let stats {
                self.stats = stats
                reachable = true
                onStats?(stats)
            } else {
                reachable = false
            }
            guard isOpen else { return }
            if structure != builtStructure { build() } else { update() }
        }
    }

    /// Everything that changes which items exist. When it differs from what
    /// was built, the menu is rebuilt; otherwise items update in place.
    private var structure: String {
        guard reachable, let stats else { return "offline" }
        return [
            String(stats.powerState?.systemOn ?? true),
            String(stats.powerState?.screenOn ?? true),
            String(stats.canSetLevel),
            stats.inputs.keys.sorted().joined(separator: ","),
            (stats.sound?.outputs ?? []).joined(separator: ","),
            (stats.picture?.modes ?? []).map(\.value).joined(separator: ","),
        ].joined(separator: "|")
    }

    // MARK: - Building

    private func build() {
        menu.removeAllItems()
        sliderView = nil
        muteItem = nil
        inputMenu = nil
        soundMenu = nil
        pictureMenu = nil
        builtStructure = structure

        let header = NSMenuItem()
        header.isEnabled = false
        menu.addItem(header)
        headerItem = header

        if reachable, let stats {
            if stats.powerState?.systemOn ?? true {
                buildControls(for: stats)
            } else {
                menu.addItem(.separator())
                menu.addItem(item("Turn On", symbol: "power", action: #selector(powerOn)))
            }
        } else {
            menu.addItem(.separator())
            let wake = item("Turn On (Wake-on-LAN)", symbol: "power", action: #selector(powerOn))
            wake.isEnabled = settings.tvMAC != nil
            menu.addItem(wake)
        }

        menu.addItem(.separator())
        buildVolumeKeysSection()

        menu.addItem(.separator())
        menu.addItem(item("Open Glasshouse Dashboard", symbol: "safari", action: #selector(openDashboard)))
        menu.addItem(item("Settings…", symbol: "gearshape", action: #selector(openSettings), key: ","))
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Glasshouse Tray", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        update()
    }

    private func buildControls(for stats: Stats) {
        menu.addItem(.separator())
        if stats.canSetLevel {
            let view = VolumeSliderView()
            view.onChange = { [weak self] level in self?.volume.set(level: level) }
            let sliderItem = NSMenuItem()
            sliderItem.view = view
            menu.addItem(sliderItem)
            sliderView = view
        } else {
            menu.addItem(item("Volume Up", symbol: "speaker.plus", action: #selector(volumeUp)))
            menu.addItem(item("Volume Down", symbol: "speaker.minus", action: #selector(volumeDown)))
        }
        let mute = item("Mute", symbol: "speaker.slash", action: #selector(toggleMute))
        menu.addItem(mute)
        muteItem = mute

        menu.addItem(.separator())
        if stats.powerState?.screenOn ?? true {
            menu.addItem(item("Turn Screen Off", symbol: "rectangle.slash", action: #selector(screenOff)))
        } else {
            menu.addItem(item("Turn Screen On", symbol: "rectangle", action: #selector(screenOn)))
        }
        menu.addItem(item("Turn Off TV", symbol: "power", action: #selector(powerOff)))

        menu.addItem(.separator())
        if !stats.inputs.isEmpty {
            inputMenu = submenu("Input", symbol: "rectangle.connected.to.line.below")
            let keys = stats.inputs.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            for key in keys {
                let entry = NSMenuItem(title: Self.inputTitle(key: key, name: stats.inputs[key] ?? key),
                                       action: #selector(selectInput(_:)), keyEquivalent: "")
                entry.target = self
                entry.representedObject = key
                inputMenu?.addItem(entry)
            }
        }
        if let outputs = stats.sound?.outputs, !outputs.isEmpty {
            soundMenu = submenu("Sound Output", symbol: "hifispeaker")
            for id in outputs {
                let entry = NSMenuItem(title: Self.soundOutputTitle(id), action: #selector(selectSoundOutput(_:)), keyEquivalent: "")
                entry.target = self
                entry.representedObject = id
                soundMenu?.addItem(entry)
            }
        }
        if let modes = stats.picture?.modes, !modes.isEmpty {
            pictureMenu = submenu("Picture Mode", symbol: "photo.tv")
            for mode in modes {
                let entry = NSMenuItem(title: mode.label ?? mode.value, action: #selector(selectPictureMode(_:)), keyEquivalent: "")
                entry.target = self
                entry.representedObject = mode.value
                pictureMenu?.addItem(entry)
            }
        }
        menu.addItem(item("Play / Pause", symbol: "playpause", action: #selector(playPause)))
    }

    private func buildVolumeKeysSection() {
        let toggle = item("Volume Keys Control TV", symbol: "keyboard", action: #selector(toggleVolumeKeys))
        toggle.state = settings.volumeKeysEnabled ? .on : .off
        menu.addItem(toggle)

        let device = audioRoute.current
        let output = NSMenuItem(title: "Output: \(device?.name ?? "None")\(audioRoute.isTV ? " (TV)" : "")",
                                action: nil, keyEquivalent: "")
        output.isEnabled = false
        output.indentationLevel = 1
        menu.addItem(output)

        if let device, !audioRoute.isTV {
            let use = item("Use “\(device.name)” as the TV", symbol: nil, action: #selector(useCurrentOutput))
            use.indentationLevel = 1
            menu.addItem(use)
        } else if settings.tvOutputUID != nil {
            let reset = item("Detect TV Output Automatically", symbol: nil, action: #selector(resetOutput))
            reset.indentationLevel = 1
            menu.addItem(reset)
        }

        if settings.volumeKeysEnabled {
            buildPermissionHealth()
        }
    }

    /// Whether the volume keys can actually be caught. A rebuilt or moved app
    /// can show as allowed in System Settings while macOS still refuses it, so
    /// a tap that should be running but isn't counts as a failure too.
    private func buildPermissionHealth() {
        let problem: String?
        if !MediaKeyTap.hasPermission {
            problem = "Accessibility access not granted"
        } else if keyTap.isEnabled, !keyTap.isActive {
            problem = "Volume keys not being caught"
        } else {
            problem = nil
        }

        guard let problem else {
            let ok = NSMenuItem(title: "Accessibility access granted", action: nil, keyEquivalent: "")
            ok.image = NSImage(systemSymbolName: "checkmark.shield", accessibilityDescription: nil)
            ok.isEnabled = false
            ok.indentationLevel = 1
            menu.addItem(ok)
            return
        }

        let status = NSMenuItem(title: problem, action: nil, keyEquivalent: "")
        status.image = NSImage(systemSymbolName: "exclamationmark.shield", accessibilityDescription: nil)
        status.isEnabled = false
        status.indentationLevel = 1
        menu.addItem(status)

        let grant = item("Open Accessibility Settings…", symbol: "lock.shield", action: #selector(openAccessibilitySettings))
        grant.indentationLevel = 1
        menu.addItem(grant)

        let note = NSMenuItem()
        note.attributedTitle = NSAttributedString(
            string: "You may need to remove it first,\nthen restart the app, then enable.",
            attributes: [
                .font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
        note.isEnabled = false
        note.indentationLevel = 1
        menu.addItem(note)

        let restart = item("Restart Glasshouse Tray", symbol: "arrow.clockwise", action: #selector(restartApp))
        restart.indentationLevel = 1
        menu.addItem(restart)
    }

    /// Refreshes the values of existing items without rebuilding.
    private func update() {
        headerItem?.attributedTitle = headerTitle()
        guard reachable, let stats else { return }

        let muted = volume.isBusy ? volume.muted : (stats.muted ?? false)
        muteItem?.state = muted ? .on : .off
        if let sliderView, !volume.isBusy, let level = stats.volume {
            sliderView.level = level
            sliderView.muted = muted
        }
        mark(inputMenu, selected: stats.app)
        mark(soundMenu, selected: stats.sound?.outputRaw)
        mark(pictureMenu, selected: stats.picture?.modeRaw)
    }

    private func headerTitle() -> NSAttributedString {
        let name = stats?.device?.name ?? "LG TV"
        let detail: String
        if !reachable {
            detail = client == nil ? "No TV address set" : "Not reachable at \(settings.host)"
        } else if let stats {
            let power = stats.powerState?.label ?? "On"
            detail = [power, stats.displayTitle].compactMap { $0 }.joined(separator: " · ")
        } else {
            detail = "Connecting…"
        }
        let title = NSMutableAttributedString(string: name, attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold),
        ])
        title.append(NSAttributedString(string: "\n" + detail, attributes: [
            .font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]))
        return title
    }

    // MARK: - Actions

    @objc private func toggleMute() {
        volume.toggleMute()
        muteItem?.state = volume.muted ? .on : .off
        sliderView?.muted = volume.muted
    }

    @objc private func volumeUp() { volume.step(up: true) }
    @objc private func volumeDown() { volume.step(up: false) }
    @objc private func screenOff() { send(.screenOff) }
    @objc private func screenOn() { send(.screenOn) }
    @objc private func powerOff() { send(.powerOff) }
    @objc private func playPause() { send(.media("playPause")) }

    @objc private func powerOn() {
        let mac = stats?.mac ?? settings.tvMAC
        let host = settings.host
        guard reachable, let client else {
            if let mac { WakeOnLAN.wake(mac: mac, host: host) }
            return
        }
        // Active Standby answers powerOn; a TV that is further asleep needs WoL.
        Task {
            do {
                try await client.send(.powerOn)
            } catch {
                if let mac { WakeOnLAN.wake(mac: mac, host: host) }
            }
            refresh()
        }
    }

    @objc private func selectInput(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        send(.input(key))
    }

    @objc private func selectSoundOutput(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        send(.soundOutput(id))
    }

    @objc private func selectPictureMode(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        send(.pictureMode(value))
    }

    @objc private func toggleVolumeKeys() {
        settings.volumeKeysEnabled.toggle()
    }

    @objc private func useCurrentOutput() {
        settings.tvOutputUID = audioRoute.current?.uid
    }

    @objc private func resetOutput() {
        settings.tvOutputUID = nil
    }

    @objc private func openAccessibilitySettings() {
        MediaKeyTap.requestPermission()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Accessibility changes for a running process often only take effect
    /// after a relaunch.
    @objc private func restartApp() {
        let path = Bundle.main.bundlePath
        let relaunch = Process()
        relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
        relaunch.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", path]
        try? relaunch.run()
        NSApp.terminate(nil)
    }

    @objc private func openDashboard() {
        guard let url = client?.dashboardURL else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func openSettings() {
        onOpenSettings?()
    }

    private func send(_ command: Command) {
        guard let client else { return }
        Task {
            do {
                try await client.send(command)
            } catch {
                onError?(error)
            }
            refresh()
        }
    }

    // MARK: - Helpers

    private func item(_ title: String, symbol: String?, action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        if let symbol {
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        }
        return item
    }

    private func submenu(_ title: String, symbol: String) -> NSMenu {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        parent.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        let submenu = NSMenu(title: title)
        submenu.autoenablesItems = false
        parent.submenu = submenu
        menu.addItem(parent)
        return submenu
    }

    private func mark(_ menu: NSMenu?, selected: String?) {
        for item in menu?.items ?? [] {
            item.state = (item.representedObject as? String) == selected ? .on : .off
        }
    }

    private static func inputTitle(key: String, name: String) -> String {
        let generic = key.uppercased().replacingOccurrences(of: "HDMI", with: "HDMI ")
        if key == "livetv" { return name.isEmpty || name == key ? "Live TV" : name }
        return name.caseInsensitiveCompare(generic) == .orderedSame ? generic : "\(name) (\(generic))"
    }

    private static let soundOutputNames = [
        "tv_speaker": "TV Speaker",
        "internal": "TV Speaker",
        "external_arc": "HDMI ARC / eARC",
        "external_optical": "Optical",
        "optical": "Optical",
        "tv_external_speaker": "Optical + TV Speaker",
        "bt_soundbar": "Bluetooth",
        "tv_speaker_bluetooth": "Bluetooth + TV Speaker",
        "headphone": "Wired Headphones / AUX",
        "tv_speaker_headphone": "Wired Headphones + TV Speaker",
        "lineout": "Line Out",
        "wow_cast": "WOW Cast",
        "mobile_phone": "Mobile Device",
        "wisa_speaker": "WiSA Speakers",
    ]

    private static func soundOutputTitle(_ id: String) -> String {
        soundOutputNames[id] ?? id.replacingOccurrences(of: "_", with: " ").capitalized
    }
}
