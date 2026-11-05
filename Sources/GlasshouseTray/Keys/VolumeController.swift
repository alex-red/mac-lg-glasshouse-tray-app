import Foundation

/// Turns volume key presses and slider moves into as few TV requests as
/// possible.
///
/// The level is tracked optimistically: each press updates it locally and
/// the HUD at once, and a single sender pushes only the newest level once the
/// previous request is done. Holding a key down therefore costs a handful of
/// requests rather than one per repeat. When the TV can't set a level (e.g.
/// an eARC soundbar), each press becomes one remote-key step instead.
@MainActor
final class VolumeController {
    var client: GlasshouseClient? {
        didSet { reset() }
    }

    /// Called whenever the level or mute state changes because of the user.
    var onDisplay: ((_ level: Int?, _ muted: Bool) -> Void)?
    var onError: ((Error) -> Void)?

    private(set) var level: Int?
    private(set) var muted = false
    private(set) var canSetLevel = true

    private let clock = ContinuousClock()
    /// After this long without a confirmed value, re-read the TV before
    /// adjusting, in case the remote changed it.
    private let staleAfter: Duration = .seconds(10)
    private var knownAt: ContinuousClock.Instant?
    private var userAt: ContinuousClock.Instant?

    private var queue: [Command] = []
    private var pendingLevel: Int?
    private var draining = false

    private var fetching = false
    private var pendingAmount = 0
    private var pendingPresses = 0

    var isBusy: Bool {
        draining || fetching || userAt.map { clock.now - $0 < .seconds(2) } ?? false
    }

    // MARK: - Input

    func handle(_ press: MediaKeyTap.Press) {
        switch press.key {
        case .volumeUp: step(up: true, fine: press.fine)
        case .volumeDown: step(up: false, fine: press.fine)
        case .mute: toggleMute()
        }
    }

    func step(up: Bool, fine: Bool = false) {
        userAt = clock.now
        let amount = (fine ? 1 : Settings.shared.volumeStep) * (up ? 1 : -1)
        if isFresh {
            apply(amount: amount, presses: up ? 1 : -1)
        } else {
            pendingAmount += amount
            pendingPresses += up ? 1 : -1
            refreshThenApplyPending()
        }
    }

    /// Absolute level from the menu slider.
    func set(level newLevel: Int) {
        userAt = clock.now
        guard canSetLevel else { return }
        setTarget(newLevel, display: false)
    }

    func toggleMute() {
        userAt = clock.now
        guard !isFresh, let client else {
            setMuted(!muted)
            return
        }
        Task {
            if let stats = try? await client.stats() { absorb(stats) }
            setMuted(!muted)
        }
    }

    func setMuted(_ on: Bool) {
        userAt = clock.now
        muted = on
        enqueue(.mute(on))
        onDisplay?(canSetLevel ? level : nil, muted)
    }

    /// Adopt the TV's reported state, unless the user is mid-adjustment.
    func sync(with stats: Stats) {
        guard !isBusy else { return }
        absorb(stats)
    }

    // MARK: - Internals

    private var isFresh: Bool {
        guard let knownAt else { return false }
        return clock.now - knownAt < staleAfter
    }

    private func absorb(_ stats: Stats) {
        canSetLevel = stats.canSetLevel
        muted = stats.muted ?? muted
        level = stats.volume
        knownAt = clock.now
    }

    private func apply(amount: Int, presses: Int) {
        if canSetLevel, let level {
            setTarget(level + amount, display: true)
        } else if presses != 0 {
            // Remote-key steps: one per press, whatever the step size.
            if muted { muted = false; enqueue(.mute(false)) }
            for _ in 0..<abs(presses) { enqueue(.volumeStep(presses > 0 ? 1 : -1)) }
            onDisplay?(nil, false)
        }
    }

    private func refreshThenApplyPending() {
        guard !fetching, let client else { return }
        fetching = true
        Task {
            defer { fetching = false }
            do {
                absorb(try await client.stats())
            } catch {
                pendingAmount = 0
                pendingPresses = 0
                onError?(error)
                return
            }
            let amount = pendingAmount, presses = pendingPresses
            pendingAmount = 0
            pendingPresses = 0
            apply(amount: amount, presses: presses)
        }
    }

    private func setTarget(_ value: Int, display: Bool) {
        let clamped = max(0, min(100, value))
        level = clamped
        knownAt = clock.now
        // Like the Mac's own volume keys, changing the level unmutes.
        if muted {
            muted = false
            queue.append(.mute(false))
        }
        pendingLevel = clamped
        if display { onDisplay?(clamped, false) }
        drain()
    }

    private func enqueue(_ command: Command) {
        queue.append(command)
        drain()
    }

    /// Sends queued commands in order, then the newest pending level.
    private func drain() {
        guard !draining, let client else { return }
        draining = true
        Task {
            defer { draining = false }
            while true {
                let command: Command
                if !queue.isEmpty {
                    command = queue.removeFirst()
                } else if let target = pendingLevel {
                    pendingLevel = nil
                    command = .volume(target)
                } else {
                    return
                }
                do {
                    try await client.send(command)
                } catch {
                    queue.removeAll()
                    pendingLevel = nil
                    knownAt = nil
                    onError?(error)
                    return
                }
            }
        }
    }

    private func reset() {
        queue.removeAll()
        pendingLevel = nil
        pendingAmount = 0
        pendingPresses = 0
        knownAt = nil
        level = nil
    }
}
