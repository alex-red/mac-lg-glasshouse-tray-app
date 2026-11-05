import Foundation

/// The `/api/control` actions this app uses. Names and values follow
/// Glasshouse's `server/lib/controls.js`.
enum Command: Sendable {
    /// Absolute level, 0–100. Moves the TV's own volume only.
    case volume(Int)
    /// ±1 sends the remote's volume key (followed by ARC/eARC receivers over CEC).
    case volumeStep(Int)
    case mute(Bool)
    case powerOn
    case powerOff
    case screenOn
    case screenOff
    /// An input key from `Stats.inputs`, e.g. `hdmi3` or `livetv`.
    case input(String)
    /// An id from `Stats.Sound.outputs`, e.g. `tv_speaker` or `external_arc`.
    case soundOutput(String)
    /// A value from `Stats.Picture.modes`, e.g. `cinema`.
    case pictureMode(String)
    /// play, pause, playPause, stop, fastForward or rewind.
    case media(String)

    var action: String {
        switch self {
        case .volume: "volume"
        case .volumeStep: "volumeStep"
        case .mute: "mute"
        case .powerOn: "powerOn"
        case .powerOff: "powerOff"
        case .screenOn: "screenOn"
        case .screenOff: "screenOff"
        case .input: "input"
        case .soundOutput: "soundOutput"
        case .pictureMode: "pictureMode"
        case .media: "media"
        }
    }

    var body: Data {
        var object: [String: Any] = ["action": action]
        switch self {
        case .volume(let level): object["value"] = max(0, min(100, level))
        case .volumeStep(let delta): object["value"] = max(-100, min(100, delta))
        case .mute(let on): object["value"] = on
        case .input(let id), .soundOutput(let id), .pictureMode(let id), .media(let id): object["value"] = id
        case .powerOn, .powerOff, .screenOn, .screenOff: break
        }
        return (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }
}
