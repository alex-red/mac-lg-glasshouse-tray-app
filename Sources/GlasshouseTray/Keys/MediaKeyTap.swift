import AppKit
import ApplicationServices

/// Intercepts the keyboard's volume keys (F10–F12 / the Touch Bar / media
/// keys) so they can be redirected to the TV.
///
/// The keys arrive as `NSSystemDefined` events (subtype 8, "aux control
/// buttons"). A session event tap sees them before the system volume
/// handler and swallows the ones it handles. The tap needs Accessibility
/// permission, and is only enabled while the TV is the audio output.
@MainActor
final class MediaKeyTap {
    enum Key {
        case volumeUp, volumeDown, mute
    }

    struct Press {
        let key: Key
        /// Shift-Option held: the system's "fine step" chord.
        let fine: Bool
        let isRepeat: Bool
    }

    var onPress: ((Press) -> Void)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    var isEnabled = false {
        didSet {
            guard isEnabled != oldValue else { return }
            if isEnabled, tap == nil { install() }
            if let tap { CGEvent.tapEnable(tap: tap, enable: isEnabled) }
        }
    }

    var isInstalled: Bool { tap != nil }

    /// Installed, valid and switched on: volume keys are actually being caught.
    var isActive: Bool {
        guard let tap else { return false }
        return CFMachPortIsValid(tap) && CGEvent.tapIsEnabled(tap: tap)
    }

    /// Sleep, display sleep and session switches can leave the tap disabled
    /// or its port invalidated without a callback. Bring it back if so.
    func revalidate() {
        guard isEnabled else { return }
        if let tap, !CFMachPortIsValid(tap) { uninstall() }
        if tap == nil { install() }
        if let tap, !CGEvent.tapIsEnabled(tap: tap) { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    static var hasPermission: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that points to Privacy & Security › Accessibility.
    static func requestPermission() {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    @discardableResult
    func install() -> Bool {
        guard tap == nil else { return true }
        let mask = CGEventMask(1) << CGEventMask(Self.systemDefined)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: mediaKeyTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: isEnabled)
        self.tap = tap
        self.source = source
        return true
    }

    private func uninstall() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        tap = nil
        source = nil
    }

    // MARK: - Event handling

    // From IOKit/hidsystem/ev_keymap.h and IOLLEvent.h.
    private static let systemDefined: UInt32 = 14            // NX_SYSDEFINED
    private static let auxControlButtons: Int16 = 8          // NX_SUBTYPE_AUX_CONTROL_BUTTONS
    private static let keyDownState = 0xA                    // NX_KEYDOWN in the high byte of the flags
    private static let soundUp = 0                           // NX_KEYTYPE_SOUND_UP
    private static let soundDown = 1                         // NX_KEYTYPE_SOUND_DOWN
    private static let mute = 7                              // NX_KEYTYPE_MUTE

    /// Returns true when the event was handled and must not reach the system.
    fileprivate func handle(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap, isEnabled { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        guard isEnabled, type.rawValue == Self.systemDefined,
              let ns = NSEvent(cgEvent: event), ns.subtype.rawValue == Self.auxControlButtons else { return false }

        let keyCode = (ns.data1 & 0xFFFF_0000) >> 16
        let keyFlags = ns.data1 & 0x0000_FFFF
        let key: Key
        switch keyCode {
        case Self.soundUp: key = .volumeUp
        case Self.soundDown: key = .volumeDown
        case Self.mute: key = .mute
        default: return false
        }

        // Swallow key-up too, so the system never sees half a press.
        let isDown = ((keyFlags & 0xFF00) >> 8) == Self.keyDownState
        if isDown {
            let flags = event.flags
            onPress?(Press(
                key: key,
                fine: flags.contains(.maskShift) && flags.contains(.maskAlternate),
                isRepeat: (keyFlags & 0x1) != 0
            ))
        }
        return true
    }
}

private func mediaKeyTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<MediaKeyTap>.fromOpaque(refcon).takeUnretainedValue()
    nonisolated(unsafe) let unsafeEvent = event
    // The tap's run loop source is on the main run loop.
    let handled = MainActor.assumeIsolated { tap.handle(type: type, event: unsafeEvent) }
    return handled ? nil : Unmanaged.passUnretained(event)
}
