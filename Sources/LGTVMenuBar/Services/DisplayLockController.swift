import AppKit
import Foundation
import Observation
import OSLog

/// What Display Lock needs from the TV side. `TVController` provides it; tests substitute a fake.
@MainActor
public protocol DisplayLockTVInterface: AnyObject {
    var configuration: TVConfiguration? { get }
    var connectionState: ConnectionState { get }
    var foreground: TVForeground { get }
    func isPCMode(inputID: String) async -> Bool?
    func readPictureMode() async throws -> String
    func setPictureMode(_ mode: String) async throws
    func setPCMode(for input: TVInputType, enabled: Bool) async throws
    func permitAutomaticAction(_ kind: ActionGovernor.Kind, reason: String) -> Bool
    func resetSuspendedAutomation()
}

extension TVController: DisplayLockTVInterface {}

/// Holds the Mac's display mode, HDR and selected TV settings to a saved profile while the TV
/// shows the Mac's input.
///
/// The cycle is: wait for things to settle, compare, apply what differs, wait, compare again.
/// Applying a change makes macOS and the TV emit the very events that trigger a cycle, so three
/// things keep it from looping: changes coalesce behind the settle delay, every write draws on
/// the shared `ActionGovernor` budget, and a correction that does not stick twice pauses the lock
/// until the user resumes it.
///
/// Nothing is applied while the displays are settling after a wake or hot-plug
/// (`DisplayStability`): re-applying 120 Hz HDR into an HDMI link that is still training starts
/// another handshake. Reconfigurations caused by the lock's own corrections are not counted.
@MainActor
@Observable
public final class DisplayLockController {
    public enum Status: Equatable, Sendable {
        case off
        case inactive(String)
        case checking
        case compliant
        case applying(String)
        case paused(String)
        /// Holding off until the displays have been quiet since a wake or reconfiguration.
        case settling
        /// The displays keep reconfiguring; holding off until they have been quiet for a minute.
        case displayUnstable
    }

    public private(set) var status: Status = .off
    public private(set) var lastAppliedAt: Date?
    public private(set) var lastApplied: [String] = []

    @ObservationIgnored private weak var tv: (any DisplayLockTVInterface)?
    @ObservationIgnored private let displayService: DisplayServiceProtocol
    @ObservationIgnored private let settleDelay: Duration
    @ObservationIgnored private let verifyDelay: Duration
    @ObservationIgnored private let maxFailuresPerCorrection = 2
    @ObservationIgnored private let logger = Logger(subsystem: "com.lgtvmenubar", category: "DisplayLock")

    @ObservationIgnored private var pendingCycle: Task<Void, Never>?
    @ObservationIgnored private var isRunningCycle = false
    @ObservationIgnored private var changeArrivedDuringCycle = false
    @ObservationIgnored private var failures: [DisplayLockCorrection: Int] = [:]
    @ObservationIgnored private var lastProfile: DisplayLockProfile?
    @ObservationIgnored private var screenObserver: NSObjectProtocol?
    @ObservationIgnored private var wakeObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var stability = DisplayStability()

    /// Receives (level, message, metadata) for every decision.
    @ObservationIgnored public var log: (String, String, [String: String]) -> Void = { _, _, _ in }

    public init(
        tv: any DisplayLockTVInterface,
        displayService: DisplayServiceProtocol,
        settleDelay: Duration = .seconds(3),
        verifyDelay: Duration = .seconds(4)
    ) {
        self.tv = tv
        self.displayService = displayService
        self.settleDelay = settleDelay
        self.verifyDelay = verifyDelay
    }

    public var displays: [DisplayInfo] { displayService.displays() }
    public var canControlHDR: Bool { displayService.canControlHDR }

    public func availableModes(forDisplayUUID uuid: String) -> [DisplayModeSpec] {
        displayService.availableModes(forDisplayUUID: uuid)
    }

    /// The display the current profile points at, if it is attached.
    public var resolvedDisplay: DisplayInfo? {
        guard let profile = tv?.configuration?.displayLock else { return nil }
        return DisplayLockEvaluator.resolveDisplay(profile: profile, displays: displayService.displays())
    }

    /// Whether the displays are settling after a wake or reconfiguration. Other writes that can
    /// start an HDMI handshake (the PC label after a wake) wait on this too.
    public var displayStability: DisplayStability.State { stability.state(at: Date()) }

    /// Starts watching macOS display reconfiguration and wakes. TV-side changes are fed in by the owner.
    public func startObservingDisplays() {
        guard screenObserver == nil else { return }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.displayReconfigured()
            }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        for (name, reason) in [(NSWorkspace.screensDidWakeNotification, "displayWoke"), (NSWorkspace.didWakeNotification, "macWoke")] {
            wakeObservers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.displayWoke(reason)
                }
            })
        }
        noteChange("started")
    }

    private func displayWoke(_ reason: String) {
        stability.noteWake(at: Date())
        record("info", "Display woke; holding display writes", ["trigger": reason, "seconds": "\(Int(DisplayStability.settleInterval))"])
        noteChange(reason)
    }

    private func displayReconfigured() {
        // The lock's own corrections reconfigure the display; those are expected, not instability.
        if !isRunningCycle {
            let wasStorm = stability.state(at: Date()).isStorm
            stability.noteReconfiguration(at: Date())
            let state = stability.state(at: Date())
            record("info", "Display reconfigured", ["state": describe(state), "displays": "\(displayService.displays().count)"])
            if !wasStorm, case .storm(let count, _) = state {
                record("error", "Display reconfiguration storm detected; Display Lock holding", ["reconfigurations": "\(count)", "withinSeconds": "\(Int(DisplayStability.stormWindow))"])
            }
        }
        noteChange("displayReconfigured")
    }

    /// The profile was edited. A new profile gets a clean slate.
    public func profileDidChange() {
        let profile = tv?.configuration?.displayLock
        if profile != lastProfile {
            lastProfile = profile
            failures.removeAll()
            if case .paused = status {
                status = .checking
            }
        }
        noteChange("profileChanged")
    }

    /// Something that could affect compliance happened. Cycles coalesce behind the settle delay.
    public func noteChange(_ reason: String) {
        if isRunningCycle {
            changeArrivedDuringCycle = true
            return
        }
        scheduleCycle(reason: reason, after: settleDelay)
    }

    private func scheduleCycle(reason: String, after delay: Duration) {
        pendingCycle?.cancel()
        pendingCycle = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            await self?.runCycle(reason: reason)
        }
    }

    /// Clears a pause and the shared automation budget, then checks again.
    public func resume() {
        failures.removeAll()
        tv?.resetSuspendedAutomation()
        status = .checking
        record("warning", "Display Lock resumed by user", [:])
        noteChange("resumed")
    }

    /// Runs any pending cycle to completion. For tests.
    func waitForIdle() async {
        while pendingCycle != nil || isRunningCycle {
            await pendingCycle?.value
            try? await Task.sleep(for: .milliseconds(2))
        }
    }

    // MARK: - Cycle

    private func runCycle(reason: String) async {
        pendingCycle = nil
        guard !isRunningCycle else {
            changeArrivedDuringCycle = true
            return
        }
        isRunningCycle = true
        defer {
            isRunningCycle = false
            if changeArrivedDuringCycle {
                changeArrivedDuringCycle = false
                noteChange("changedDuringCycle")
            }
        }

        if case .paused = status { return }

        let stabilityState = stability.state(at: Date())
        if tv?.configuration?.displayLock.isEnabled == true, let until = stabilityState.until {
            setStatus(stabilityState.isStorm ? .displayUnstable : .settling, reason: reason)
            record("info", "Display Lock held - display not settled", ["state": describe(stabilityState), "trigger": reason])
            scheduleCycle(reason: "displaySettled", after: .seconds(max(until.timeIntervalSinceNow, 0) + 0.5))
            return
        }

        let evaluation = await evaluate()
        switch evaluation {
        case .inactive(let why):
            setStatus(tv?.configuration?.displayLock.isEnabled == true ? .inactive(why) : .off, reason: reason)
        case .compliant:
            failures.removeAll()
            setStatus(.compliant, reason: reason)
        case .drift(let corrections):
            await correct(corrections, reason: reason)
        }
    }

    private func correct(_ corrections: [DisplayLockCorrection], reason: String) async {
        guard let tv else { return }
        var applied: [String] = []
        var failedToApply: Set<DisplayLockCorrection> = []

        for correction in corrections {
            guard tv.permitAutomaticAction(correction.governorKind, reason: "displayLock") else {
                pause("Too many automatic changes in a short time. Display Lock is paused so it cannot loop.")
                return
            }

            status = .applying(correction.label)
            record("info", "Display Lock applying", ["correction": correction.label, "trigger": reason])
            do {
                try await apply(correction)
                applied.append(correction.label)
            } catch {
                failedToApply.insert(correction)
                failures[correction, default: 0] += 1
                record("error", "Display Lock could not apply", ["correction": correction.label, "error": error.localizedDescription, "failures": "\(failures[correction] ?? 0)"])
                if failures[correction, default: 0] >= maxFailuresPerCorrection {
                    pause("Could not set \(correction.label): \(error.localizedDescription)")
                    return
                }
            }
        }

        if !applied.isEmpty {
            lastApplied = applied
            lastAppliedAt = Date()
        }

        // Give macOS and the TV time to renegotiate before judging the result.
        try? await Task.sleep(for: verifyDelay)

        switch await evaluate() {
        case .compliant:
            failures.removeAll()
            setStatus(.compliant, reason: "verified")
        case .inactive(let why):
            setStatus(.inactive(why), reason: "verified")
        case .drift(let remaining):
            // A correction that threw was already counted once; do not count it again here.
            for correction in remaining where corrections.contains(correction) && !failedToApply.contains(correction) {
                failures[correction, default: 0] += 1
            }
            if let stuck = remaining.first(where: { failures[$0, default: 0] >= maxFailuresPerCorrection }) {
                pause("\(stuck.label.prefix(1).uppercased() + stuck.label.dropFirst()) did not stay set. Display Lock is paused so it cannot loop.")
            } else {
                record("warning", "Display Lock change did not hold yet; will retry", ["remaining": remaining.map(\.label).joined(separator: ", ")])
                changeArrivedDuringCycle = true
            }
        }
    }

    private func evaluate() async -> DisplayLockEvaluation {
        guard let tv, let config = tv.configuration else {
            return .inactive("No TV is configured")
        }
        let profile = config.displayLock
        var snapshot = DisplayLockSnapshot(
            isConnected: tv.connectionState.isConnected,
            foreground: tv.foreground,
            preferredInput: config.preferredInput,
            display: DisplayLockEvaluator.resolveDisplay(profile: profile, displays: displayService.displays())
        )

        // Only ask the TV for more when the lock is in play at all.
        if case .inactive = DisplayLockEvaluator.evaluate(profile: profile, snapshot: snapshot) {
            return DisplayLockEvaluator.evaluate(profile: profile, snapshot: snapshot)
        }

        if profile.enforcePCMode {
            snapshot.inputIsPCMode = await tv.isPCMode(inputID: profile.effectiveInputID(preferredInput: config.preferredInput))
        }
        if profile.pictureMode != nil {
            do {
                snapshot.pictureMode = try await tv.readPictureMode()
            } catch {
                record("warning", "Display Lock could not read the picture mode", ["error": error.localizedDescription])
            }
        }

        return DisplayLockEvaluator.evaluate(profile: profile, snapshot: snapshot)
    }

    private func apply(_ correction: DisplayLockCorrection) async throws {
        guard let tv, let config = tv.configuration else { return }
        let profile = config.displayLock

        switch correction {
        case .displayMode(let mode):
            guard let display = DisplayLockEvaluator.resolveDisplay(profile: profile, displays: displayService.displays()) else {
                throw DisplayServiceError.displayNotFound
            }
            try displayService.setMode(mode, displayUUID: display.uuid)
        case .hdr(let enabled):
            guard let display = DisplayLockEvaluator.resolveDisplay(profile: profile, displays: displayService.displays()) else {
                throw DisplayServiceError.displayNotFound
            }
            try displayService.setHDR(enabled, displayUUID: display.uuid)
        case .pcMode:
            guard let input = TVInputType(rawValue: profile.effectiveInputID(preferredInput: config.preferredInput)) else { return }
            try await tv.setPCMode(for: input, enabled: true)
        case .pictureMode(let mode):
            try await tv.setPictureMode(mode)
        }
    }

    private func pause(_ message: String) {
        status = .paused(message)
        record("error", "Display Lock paused", ["reason": message])
    }

    private func setStatus(_ newStatus: Status, reason: String) {
        guard status != newStatus else { return }
        record("info", "Display Lock status", ["from": "\(status)", "to": "\(newStatus)", "trigger": reason])
        status = newStatus
    }

    private func describe(_ state: DisplayStability.State) -> String {
        switch state {
        case .stable: return "stable"
        case .settling(let until): return "settling for \(Int(until.timeIntervalSinceNow.rounded(.up)))s"
        case .storm(let count, let until): return "storm (\(count) reconfigurations), holding \(Int(until.timeIntervalSinceNow.rounded(.up)))s"
        }
    }

    /// Written at notice or above so macOS keeps it on disk: these are what explain a display
    /// incident after the fact (`log show --predicate 'subsystem == "com.lgtvmenubar"'`).
    private func record(_ level: String, _ message: String, _ metadata: [String: String]) {
        let line = "\(message) \(metadata.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))"
        switch level {
        case "error": logger.error("\(line, privacy: .public)")
        case "warning": logger.warning("\(line, privacy: .public)")
        default: logger.notice("\(line, privacy: .public)")
        }
        log(level, message, metadata)
    }
}
