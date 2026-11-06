import CoreAudio
import Foundation

/// Tracks the system's default output device and whether it is the TV.
///
/// Event-driven via a CoreAudio property listener; nothing polls.
@MainActor
final class AudioRoute {
    struct Device: Equatable {
        let id: AudioDeviceID
        let uid: String
        let name: String
        let transport: UInt32

        var isDisplayLink: Bool {
            transport == kAudioDeviceTransportTypeHDMI || transport == kAudioDeviceTransportTypeDisplayPort
        }
    }

    private(set) var current: Device?
    private(set) var isTV = false
    var onChange: (() -> Void)?

    private var listener: AudioObjectPropertyListenerBlock?
    private var settleWork: DispatchWorkItem?
    // The default device, plus the device list: a display's HDMI device can
    // become the default before its name and transport are readable, and
    // only the device list changes again once they are.
    private var addresses = [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDevices].map {
        AudioObjectPropertyAddress(
            mSelector: $0,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    func start() {
        guard listener == nil else { return }
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.refreshSettling() }
        }
        listener = block
        for i in addresses.indices {
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addresses[i], .main, block)
        }
        refresh()
    }

    /// Refreshes now and again shortly after, for devices that are still
    /// coming up (after wake, or when the display turns back on).
    func refreshSettling() {
        refresh()
        settleWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.refresh() }
        }
        settleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }

    func refresh() {
        let device = Self.defaultOutputDevice()
        let tv = device.map(matchesTV) ?? false
        guard device != current || tv != isTV else { return }
        current = device
        isTV = tv
        onChange?()
    }

    private func matchesTV(_ device: Device) -> Bool {
        if let uid = Settings.shared.tvOutputUID {
            return device.uid == uid
        }
        return device.isDisplayLink && device.name.localizedCaseInsensitiveContains("LG")
    }

    // MARK: - CoreAudio

    private static func defaultOutputDevice() -> Device? {
        var id = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id) == noErr,
              id != kAudioObjectUnknown else { return nil }

        var transport: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        address.mSelector = kAudioDevicePropertyTransportType
        AudioObjectGetPropertyData(id, &address, 0, nil, &size, &transport)

        return Device(
            id: id,
            uid: string(kAudioDevicePropertyDeviceUID, of: id) ?? "",
            name: string(kAudioObjectPropertyName, of: id) ?? "Unknown",
            transport: transport
        )
    }

    private static func string(_ selector: AudioObjectPropertySelector, of id: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, $0)
        }
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }
}
