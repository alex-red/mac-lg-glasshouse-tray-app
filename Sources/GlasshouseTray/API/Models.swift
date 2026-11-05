import Foundation

struct Caps: Decodable, Sendable {
    let ok: Bool
    let allowControl: Bool?
    let allowPower: Bool?
    let version: String?
}

/// The subset of `GET /api/stats` the app reads.
///
/// The payload varies with webOS version, model and power state, so every
/// field decodes leniently: one unexpected value leaves that field `nil`
/// instead of failing the whole snapshot.
struct Stats: Decodable, Sendable {
    struct Device: Decodable, Sendable {
        let name: String?
        let model: String?
    }

    struct Power: Decodable, Sendable {
        let raw: String?
        let label: String?
        let systemOn: Bool?
        let screenOn: Bool?
    }

    struct Sound: Decodable, Sendable {
        let output: String?
        let outputRaw: String?
        let outputs: [String]

        private enum CodingKeys: String, CodingKey {
            case output, outputs
            case outputRaw = "output_raw"
        }

        private struct Entry: Decodable {
            let id: String
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            output = c.lenient(String.self, .output)
            outputRaw = c.lenient(String.self, .outputRaw)
            // Plain ids on current servers; {id, name} objects on some older ones.
            outputs = c.lenient([String].self, .outputs)
                ?? c.lenient([Entry].self, .outputs)?.map(\.id)
                ?? []
        }
    }

    struct PictureMode: Decodable, Sendable {
        let value: String
        let label: String?
    }

    struct Picture: Decodable, Sendable {
        let modeRaw: String?
        let modes: [PictureMode]

        private enum CodingKeys: String, CodingKey {
            case modes
            case modeRaw = "mode_raw"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            modeRaw = c.lenient(String.self, .modeRaw)
            modes = c.lenient([PictureMode].self, .modes) ?? []
        }
    }

    let device: Device?
    /// `nil` when the level is not the TV's to set (e.g. an eARC soundbar).
    let volume: Int?
    let muted: Bool?
    /// `level`, `step` or `none`.
    let volumeControl: String?
    let powerState: Power?
    /// Short id of the foreground app: `hdmi3`, `livetv`, `netflix`, …
    let app: String?
    let displayTitle: String?
    /// Input key → the name given to it on the TV.
    let inputs: [String: String]
    let sound: Sound?
    let picture: Picture?
    let mac: String?

    private enum CodingKeys: String, CodingKey {
        case device, volume, muted, powerState, app, inputs, sound, picture, mac
        case volumeControl = "volume_control"
        case displayTitle = "display_title"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        device = c.lenient(Device.self, .device)
        volume = c.lenient(Int.self, .volume) ?? c.lenient(Double.self, .volume).map { Int($0.rounded()) }
        muted = c.lenient(Bool.self, .muted)
        volumeControl = c.lenient(String.self, .volumeControl)
        powerState = c.lenient(Power.self, .powerState)
        app = c.lenient(String.self, .app)
        displayTitle = c.lenient(String.self, .displayTitle)
        inputs = c.lenient([String: String].self, .inputs) ?? [:]
        sound = c.lenient(Sound.self, .sound)
        picture = c.lenient(Picture.self, .picture)
        mac = c.lenient(String.self, .mac)
    }

    var canSetLevel: Bool {
        volume != nil && (volumeControl ?? "level") == "level"
    }
}

extension KeyedDecodingContainer {
    func lenient<T: Decodable>(_ type: T.Type, _ key: Key) -> T? {
        try? decodeIfPresent(type, forKey: key)
    }
}
