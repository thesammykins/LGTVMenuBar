import Testing
import Foundation
@testable import LGTVMenuBar

private let mode4K120 = DisplayModeSpec(pixelWidth: 3840, pixelHeight: 2160, pointWidth: 3840, pointHeight: 2160, refreshRate: 120)
private let mode4K60 = DisplayModeSpec(pixelWidth: 3840, pixelHeight: 2160, pointWidth: 3840, pointHeight: 2160, refreshRate: 60)

private func lgDisplay(uuid: String = "LG-1", mode: DisplayModeSpec? = mode4K120, hdrSupported: Bool = true, hdrEnabled: Bool = true) -> DisplayInfo {
    DisplayInfo(displayID: 2, uuid: uuid, name: "LG TV", vendorID: DisplayInfo.lgVendorID, isBuiltIn: false, currentMode: mode, hdrSupported: hdrSupported, hdrEnabled: hdrEnabled)
}

@Suite("DisplayLockEvaluator")
struct DisplayLockEvaluatorTests {
    private let profile = DisplayLockProfile(isEnabled: true, mode: mode4K120, hdrEnabled: true, enforcePCMode: true, pictureMode: "game")

    private func snapshot(
        connected: Bool = true,
        foreground: TVForeground = .input(.hdmi1),
        display: DisplayInfo? = lgDisplay(),
        pc: Bool? = true,
        picture: String? = "game"
    ) -> DisplayLockSnapshot {
        DisplayLockSnapshot(isConnected: connected, foreground: foreground, preferredInput: "HDMI_1", display: display, inputIsPCMode: pc, pictureMode: picture)
    }

    @Test("a disabled or empty profile is inactive")
    func disabledOrEmpty() {
        #expect(DisplayLockEvaluator.evaluate(profile: DisplayLockProfile(isEnabled: false, mode: mode4K120), snapshot: snapshot()) == .inactive("Display Lock is off"))
        #expect(DisplayLockEvaluator.evaluate(profile: DisplayLockProfile(isEnabled: true), snapshot: snapshot()) == .inactive("Nothing is locked yet"))
    }

    @Test("the lock has no effect on any other input, on apps, or when the foreground is unknown")
    func otherForeground() {
        let drifted = lgDisplay(mode: mode4K60, hdrEnabled: false)
        #expect(DisplayLockEvaluator.evaluate(profile: profile, snapshot: snapshot(foreground: .input(.hdmi2), display: drifted)) == .inactive("TV is on HDMI 2"))
        #expect(DisplayLockEvaluator.evaluate(profile: profile, snapshot: snapshot(foreground: .app("netflix"), display: drifted)) == .inactive("TV is showing an app"))
        #expect(DisplayLockEvaluator.evaluate(profile: profile, snapshot: snapshot(foreground: .unknown, display: drifted)) == .inactive("Waiting to learn what the TV is showing"))
    }

    @Test("the lock is inactive while disconnected")
    func disconnected() {
        #expect(DisplayLockEvaluator.evaluate(profile: profile, snapshot: snapshot(connected: false)) == .inactive("Not connected to the TV"))
    }

    @Test("a profile bound to a specific input follows that input, not the preferred one")
    func explicitInput() {
        var bound = profile
        bound.inputID = "HDMI_3"
        #expect(DisplayLockEvaluator.evaluate(profile: bound, snapshot: snapshot(foreground: .input(.hdmi3))) == .compliant)
        #expect(DisplayLockEvaluator.evaluate(profile: bound, snapshot: snapshot(foreground: .input(.hdmi1))) == .inactive("TV is on HDMI 1"))
    }

    @Test("matching state is compliant, including refresh-rate rounding noise")
    func compliant() {
        let noisy = DisplayModeSpec(pixelWidth: 3840, pixelHeight: 2160, pointWidth: 3840, pointHeight: 2160, refreshRate: 120.00001)
        #expect(DisplayLockEvaluator.evaluate(profile: profile, snapshot: snapshot(display: lgDisplay(mode: noisy))) == .compliant)
    }

    @Test("each difference becomes a correction, Mac side first")
    func drift() {
        let evaluation = DisplayLockEvaluator.evaluate(
            profile: profile,
            snapshot: snapshot(display: lgDisplay(mode: mode4K60, hdrEnabled: false), pc: false, picture: "vivid")
        )
        #expect(evaluation == .drift([.displayMode(mode4K120), .hdr(true), .pcMode, .pictureMode("game")]))
    }

    @Test("unknown TV values are never corrected")
    func unknownValues() {
        #expect(DisplayLockEvaluator.evaluate(profile: profile, snapshot: snapshot(pc: nil, picture: nil)) == .compliant)
    }

    @Test("HDR is not requested from a display that cannot do it")
    func hdrUnsupported() {
        #expect(DisplayLockEvaluator.evaluate(profile: profile, snapshot: snapshot(display: lgDisplay(hdrSupported: false, hdrEnabled: false))) == .compliant)
    }

    @Test("Mac-side settings need the TV attached as a display")
    func displayMissing() {
        #expect(DisplayLockEvaluator.evaluate(profile: profile, snapshot: snapshot(display: nil)) == .inactive("The TV is not connected to this Mac as a display"))
        let tvOnly = DisplayLockProfile(isEnabled: true, pictureMode: "game")
        #expect(DisplayLockEvaluator.evaluate(profile: tvOnly, snapshot: snapshot(display: nil, picture: "vivid")) == .drift([.pictureMode("game")]))
    }

    @Test("the display is the saved one, or the only LG display")
    func resolveDisplay() {
        let other = DisplayInfo(displayID: 1, uuid: "OTHER", name: "Other", vendorID: 0x0E58, isBuiltIn: false, currentMode: nil, hdrSupported: false, hdrEnabled: false)
        #expect(DisplayLockEvaluator.resolveDisplay(profile: DisplayLockProfile(), displays: [other, lgDisplay()])?.uuid == "LG-1")
        #expect(DisplayLockEvaluator.resolveDisplay(profile: DisplayLockProfile(), displays: [lgDisplay(uuid: "A"), lgDisplay(uuid: "B")]) == nil)
        #expect(DisplayLockEvaluator.resolveDisplay(profile: DisplayLockProfile(displayUUID: "OTHER"), displays: [other, lgDisplay()])?.uuid == "OTHER")
        #expect(DisplayLockEvaluator.resolveDisplay(profile: DisplayLockProfile(displayUUID: "GONE"), displays: [lgDisplay()]) == nil)
    }
}

@MainActor
private final class FakeDisplayService: DisplayServiceProtocol {
    var display = lgDisplay(mode: mode4K60, hdrEnabled: false)
    var canControlHDR = true
    /// When false, writes are accepted but have no effect (macOS or the TV reverting them).
    var writesStick = true
    var setModeError: Error?
    private(set) var setModeCalls: [DisplayModeSpec] = []
    private(set) var setHDRCalls: [Bool] = []

    func displays() -> [DisplayInfo] { [display] }
    func availableModes(forDisplayUUID uuid: String) -> [DisplayModeSpec] { [mode4K120, mode4K60] }

    func setMode(_ mode: DisplayModeSpec, displayUUID: String) throws {
        setModeCalls.append(mode)
        if let setModeError { throw setModeError }
        guard writesStick else { return }
        display = DisplayInfo(displayID: display.displayID, uuid: display.uuid, name: display.name, vendorID: display.vendorID, isBuiltIn: false, currentMode: mode, hdrSupported: display.hdrSupported, hdrEnabled: display.hdrEnabled)
    }

    func setHDR(_ enabled: Bool, displayUUID: String) throws {
        setHDRCalls.append(enabled)
        guard writesStick else { return }
        display = DisplayInfo(displayID: display.displayID, uuid: display.uuid, name: display.name, vendorID: display.vendorID, isBuiltIn: false, currentMode: display.currentMode, hdrSupported: display.hdrSupported, hdrEnabled: enabled)
    }
}

@MainActor
private final class FakeLockTV: DisplayLockTVInterface {
    var configuration: TVConfiguration?
    var connectionState: ConnectionState = .connected
    var foreground: TVForeground = .input(.hdmi1)
    var pcMode = false
    var pictureMode = "vivid"
    var governor = ActionGovernor()
    private(set) var setPCModeCalls = 0
    private(set) var setPictureModeCalls: [String] = []
    private(set) var resetCalls = 0

    init(profile: DisplayLockProfile) {
        var config = TVConfiguration(name: "TV", ipAddress: "10.0.0.2", macAddress: "AA:BB:CC:DD:EE:FF", preferredInput: "HDMI_1")
        config.displayLock = profile
        configuration = config
    }

    func isPCMode(inputID: String) async -> Bool? { pcMode }
    func readPictureMode() async throws -> String { pictureMode }
    func setPictureMode(_ mode: String) async throws { setPictureModeCalls.append(mode); pictureMode = mode }
    func setPCMode(for input: TVInputType, enabled: Bool) async throws { setPCModeCalls += 1; pcMode = enabled }
    func permitAutomaticAction(_ kind: ActionGovernor.Kind, reason: String) -> Bool { governor.request(kind).isAllowed }
    func resetSuspendedAutomation() { resetCalls += 1; governor.reset() }
}

@Suite("DisplayLockController")
@MainActor
struct DisplayLockControllerTests {
    private let fullProfile = DisplayLockProfile(isEnabled: true, mode: mode4K120, hdrEnabled: true, enforcePCMode: true, pictureMode: "game")

    /// The lock holds its TV weakly, as it does the real controller. Tests that do not otherwise
    /// use the fake keep it alive through this list.
    private final class Retainer { var objects: [AnyObject] = [] }
    private let retainer = Retainer()

    private func makeLock(profile: DisplayLockProfile) -> (DisplayLockController, FakeLockTV, FakeDisplayService) {
        let tv = FakeLockTV(profile: profile)
        retainer.objects.append(tv)
        let displays = FakeDisplayService()
        let lock = DisplayLockController(tv: tv, displayService: displays, settleDelay: .milliseconds(5), verifyDelay: .milliseconds(5))
        return (lock, tv, displays)
    }

    @Test("drift on the locked input is corrected once and then verified")
    func correctsDrift() async {
        let (lock, tv, displays) = makeLock(profile: fullProfile)

        lock.noteChange("test")
        await lock.waitForIdle()

        #expect(displays.setModeCalls == [mode4K120])
        #expect(displays.setHDRCalls == [true])
        #expect(tv.setPCModeCalls == 1)
        #expect(tv.setPictureModeCalls == ["game"])
        #expect(lock.status == .compliant)
        #expect(lock.lastApplied.count == 4)
    }

    @Test("nothing is touched while the TV is on another input")
    func inactiveOnOtherInput() async {
        let (lock, tv, displays) = makeLock(profile: fullProfile)
        tv.foreground = .input(.hdmi2)

        lock.noteChange("test")
        await lock.waitForIdle()

        #expect(displays.setModeCalls.isEmpty && displays.setHDRCalls.isEmpty)
        #expect(tv.setPCModeCalls == 0 && tv.setPictureModeCalls.isEmpty)
        #expect(lock.status == .inactive("TV is on HDMI 2"))
    }

    @Test("switching back to the locked input applies the profile")
    func appliesOnReturn() async {
        let (lock, tv, displays) = makeLock(profile: DisplayLockProfile(isEnabled: true, mode: mode4K120))
        tv.foreground = .app("netflix")
        lock.noteChange("test")
        await lock.waitForIdle()
        #expect(displays.setModeCalls.isEmpty)

        tv.foreground = .input(.hdmi1)
        lock.noteChange("foreground")
        await lock.waitForIdle()
        #expect(displays.setModeCalls == [mode4K120])
        #expect(lock.status == .compliant)
    }

    @Test("a burst of changes produces one correction pass")
    func coalesces() async {
        let (lock, _, displays) = makeLock(profile: DisplayLockProfile(isEnabled: true, mode: mode4K120))
        for index in 0..<20 { lock.noteChange("burst \(index)") }
        await lock.waitForIdle()
        #expect(displays.setModeCalls.count == 1)
    }

    @Test("a setting that will not stay set pauses the lock instead of looping")
    func pausesWhenChangeDoesNotStick() async {
        let (lock, _, displays) = makeLock(profile: DisplayLockProfile(isEnabled: true, hdrEnabled: true))
        displays.writesStick = false

        lock.noteChange("test")
        await lock.waitForIdle()

        #expect(displays.setHDRCalls.count == 2)
        guard case .paused(let message) = lock.status else {
            Issue.record("expected the lock to pause, got \(lock.status)")
            return
        }
        #expect(message.contains("HDR on"))

        // Further events do nothing while paused.
        lock.noteChange("more")
        await lock.waitForIdle()
        #expect(displays.setHDRCalls.count == 2)
    }

    @Test("a write that keeps failing pauses the lock")
    func pausesWhenWriteFails() async {
        let (lock, _, displays) = makeLock(profile: DisplayLockProfile(isEnabled: true, mode: mode4K120))
        displays.setModeError = DisplayServiceError.modeNotAvailable("3840 × 2160, 120 Hz")

        lock.noteChange("test")
        await lock.waitForIdle()

        #expect(displays.setModeCalls.count == 2)
        guard case .paused = lock.status else {
            Issue.record("expected the lock to pause, got \(lock.status)")
            return
        }
    }

    @Test("an exhausted automation budget pauses the lock before it writes")
    func governorRefusalPauses() async {
        let (lock, tv, displays) = makeLock(profile: DisplayLockProfile(isEnabled: true, mode: mode4K120))
        tv.governor = ActionGovernor(limits: [.displayModeChange: .init(maxActions: 1, window: 600, cooldown: 600)])
        _ = tv.governor.request(.displayModeChange)

        lock.noteChange("test")
        await lock.waitForIdle()

        #expect(displays.setModeCalls.isEmpty)
        guard case .paused = lock.status else {
            Issue.record("expected the lock to pause, got \(lock.status)")
            return
        }
    }

    @Test("resume clears the pause and tries again")
    func resume() async {
        let (lock, tv, displays) = makeLock(profile: DisplayLockProfile(isEnabled: true, hdrEnabled: true))
        displays.writesStick = false
        lock.noteChange("test")
        await lock.waitForIdle()

        displays.writesStick = true
        lock.resume()
        await lock.waitForIdle()

        #expect(tv.resetCalls == 1)
        #expect(lock.status == .compliant)
    }

    @Test("editing the profile clears a pause")
    func profileChangeClearsPause() async {
        let (lock, tv, displays) = makeLock(profile: DisplayLockProfile(isEnabled: true, hdrEnabled: true))
        displays.writesStick = false
        lock.profileDidChange()
        await lock.waitForIdle()
        guard case .paused = lock.status else {
            Issue.record("expected the lock to pause first")
            return
        }

        tv.configuration?.displayLock = DisplayLockProfile(isEnabled: false)
        lock.profileDidChange()
        await lock.waitForIdle()
        #expect(lock.status == .off)
    }
}
