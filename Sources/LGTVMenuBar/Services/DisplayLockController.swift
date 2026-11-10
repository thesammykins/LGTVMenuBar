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

    /// Starts watching macOS display reconfiguration. TV-side changes are fed in by the owner.
    public func startObservingDisplays() {
        guard screenObserver == nil else { return }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.noteChange("displayReconfigured")
            }
        }
        noteChange("started")
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
        pendingCycle?.cancel()
        pendingCycle = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: self.settleDelay)
            } catch {
                return
            }
            await self.runCycle(reason: reason)
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

    private func record(_ level: String, _ message: String, _ metadata: [String: String]) {
        logger.info("\(message, privacy: .public) \(metadata, privacy: .public)")
        log(level, message, metadata)
    }
}
