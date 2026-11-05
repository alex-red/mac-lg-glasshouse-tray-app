import AppKit

/// The settings sheet: a modal alert with a small form, which needs no
/// window controller.
@MainActor
enum SettingsPanel {
    static func present() {
        let settings = Settings.shared

        let host = NSTextField(string: settings.host)
        host.placeholderString = "192.168.1.50"
        let port = NSTextField(string: String(settings.port))
        let token = NSSecureTextField(string: settings.token ?? "")
        token.placeholderString = "Only if one is set on the TV"
        let step = NSPopUpButton()
        step.addItems(withTitles: (1...5).map(String.init))
        step.selectItem(withTitle: String(settings.volumeStep))
        let login = NSButton(checkboxWithTitle: "Open at login", target: nil, action: nil)
        login.state = LaunchAtLogin.isEnabled ? .on : .off

        let grid = NSGridView(views: [
            [label("TV address:"), host],
            [label("Port:"), port],
            [label("API token:"), token],
            [label("Volume step:"), step],
            [NSGridCell.emptyContentView, login],
        ])
        grid.rowSpacing = 8
        grid.columnSpacing = 8
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        host.widthAnchor.constraint(equalToConstant: 220).isActive = true
        port.widthAnchor.constraint(equalToConstant: 70).isActive = true
        token.widthAnchor.constraint(equalTo: host.widthAnchor).isActive = true
        grid.frame = NSRect(origin: .zero, size: grid.fittingSize)

        let alert = NSAlert()
        alert.messageText = "Glasshouse Tray Settings"
        alert.informativeText = "The address of an LG TV running Glasshouse. Shift-Option with a volume key always moves one step."
        alert.accessoryView = grid
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = host

        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        settings.volumeStep = Int(step.titleOfSelectedItem ?? "") ?? settings.volumeStep
        let newHost = host.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !newHost.isEmpty, newHost != settings.host { settings.host = newHost }
        if let newPort = Int(port.stringValue), (1...65_535).contains(newPort), newPort != settings.port {
            settings.port = newPort
        }
        let newToken = token.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if newToken != (settings.token ?? "") { settings.token = newToken }
        let wantsLogin = login.state == .on
        if wantsLogin != LaunchAtLogin.isEnabled { LaunchAtLogin.set(wantsLogin) }
    }

    private static func label(_ text: String) -> NSTextField {
        NSTextField(labelWithString: text)
    }
}
