import Foundation

@MainActor
final class Settings {
    static let shared = Settings()

    static let didChange = Notification.Name("GlasshouseTraySettingsDidChange")

    private let defaults = UserDefaults.standard

    var host: String {
        get { defaults.string(forKey: "host") ?? "" }
        set { defaults.set(newValue, forKey: "host"); changed() }
    }

    var port: Int {
        get { (defaults.object(forKey: "port") as? Int) ?? 8080 }
        set { defaults.set(newValue, forKey: "port"); changed() }
    }

    var token: String? {
        get { Keychain.read(account: "token") }
        set {
            if let newValue, !newValue.isEmpty {
                Keychain.write(newValue, account: "token")
            } else {
                Keychain.delete(account: "token")
            }
            changed()
        }
    }

    /// TV volume units moved by one key press (Shift-Option always moves 1).
    var volumeStep: Int {
        get { max(1, (defaults.object(forKey: "volumeStep") as? Int) ?? 2) }
        set { defaults.set(max(1, min(10, newValue)), forKey: "volumeStep") }
    }

    var volumeKeysEnabled: Bool {
        get { (defaults.object(forKey: "volumeKeysEnabled") as? Bool) ?? true }
        set { defaults.set(newValue, forKey: "volumeKeysEnabled"); changed() }
    }

    /// CoreAudio UID of the output device that is the TV. When unset, any
    /// HDMI or DisplayPort output whose name contains "LG" counts.
    var tvOutputUID: String? {
        get { defaults.string(forKey: "tvOutputUID") }
        set { defaults.set(newValue, forKey: "tvOutputUID"); changed() }
    }

    /// Last MAC address the TV reported, kept for Wake-on-LAN while it is off.
    var tvMAC: String? {
        get { defaults.string(forKey: "tvMAC") }
        set { defaults.set(newValue, forKey: "tvMAC") }
    }

    func makeClient() -> GlasshouseClient? {
        GlasshouseClient(host: host, port: port, token: token)
    }

    private func changed() {
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }
}
