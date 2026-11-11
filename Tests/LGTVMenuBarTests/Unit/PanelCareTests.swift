import Testing
import Foundation
@testable import LGTVMenuBar

/// Replies captured from an LG C2 (webOS 7, kernel 5.4.268) on 2026-11-10.
private let capturedPanelCareOutput = """
utt={"oledPanelUTT":6133,"returnValue":true}
info={"returnValue":true,"jbLastTime":5592,"jbCount":11,"jbInterval":500,"pnwashKeyLock":true,"offrsInterval":4,"offrsLastTime":6019,"offrsCount":424,"subscribed":false}
cond={"returnValue":true,"isCondition":true}
"""

private func status(due: Bool) -> PanelCareStatus {
    PanelCareStatus(panelHours: 100, refreshCount: 1, longRefreshCount: 0, isRefreshDue: due)
}

@Suite("PanelCareStatus")
struct PanelCareStatusTests {
    @Test("the TV's replies are parsed into hours and due flags")
    func parseCaptured() throws {
        let status = try #require(PanelCareStatus.parse(capturedPanelCareOutput))
        #expect(status == PanelCareStatus(panelHours: 6133, refreshCount: 424, longRefreshCount: 11, isRefreshDue: true, refreshIntervalHours: 4, longRefreshIntervalHours: 500))
    }

    @Test("after a refresh the count has gone up and nothing is due")
    func parseAfterRefresh() throws {
        // Captured the morning after: the last-refresh field (6037) is not on the panel-hours
        // clock (6140), which is why use since the last refresh is not derived from it.
        let output = """
        utt={"oledPanelUTT":6140,"returnValue":true}
        info={"returnValue":true,"jbLastTime":5592,"jbCount":11,"jbInterval":500,"pnwashKeyLock":true,"offrsInterval":4,"offrsLastTime":6037,"offrsCount":425,"subscribed":false}
        cond={"returnValue":true,"isCondition":false}
        """
        #expect(PanelCareStatus.parse(output) == PanelCareStatus(panelHours: 6140, refreshCount: 425, longRefreshCount: 11, isRefreshDue: false, refreshIntervalHours: 4, longRefreshIntervalHours: 500))
    }

    @Test("a TV without the panel-care service reads as not available")
    func parseMissing() {
        #expect(PanelCareStatus.parse("utt=\ninfo=\ncond=") == nil)
        #expect(PanelCareStatus.parse(#"utt={"returnValue":false,"errorText":"no such service"}"#) == nil)
        #expect(PanelCareStatus.parse("") == nil)
    }
}

@Suite("PanelCarePolicy")
struct PanelCarePolicyTests {
    private func decision(enabled: Bool = true, locked: Bool = true, status: PanelCareStatus? = status(due: true), connected: Bool = true, foreground: TVForeground = .input(.hdmi1), withinHours: Bool = true) -> PanelCarePolicy.PowerOffDecision {
        PanelCarePolicy.powerOffDecision(isEnabled: enabled, isMacLocked: locked, isWithinAllowedHours: withinHours, status: status, isConnected: connected, foreground: foreground, preferredInput: "HDMI_1")
    }

    @Test("the TV is switched off only when a refresh is due and the Mac's input is in front")
    func powerOff() {
        #expect(decision() == .powerOff)
        #expect(decision(enabled: false) == .leaveOn(reason: "panel care is off"))
        #expect(decision(locked: false) == .leaveOn(reason: "the Mac is not locked"))
        #expect(decision(withinHours: false) == .leaveOn(reason: "outside the set hours"))
        // Being inside the set hours never stands in for the Mac being locked.
        #expect(decision(locked: false, withinHours: true) == .leaveOn(reason: "the Mac is not locked"))
        #expect(decision(status: status(due: false)) == .leaveOn(reason: "no refresh is due"))
        #expect(decision(status: nil) == .leaveOn(reason: "panel-care state is not available"))
        #expect(decision(connected: false) == .leaveOn(reason: "not connected to the TV"))
        #expect(decision(foreground: .input(.hdmi2)) == .leaveOn(reason: "TV is on HDMI 2"))
        #expect(decision(foreground: .app("netflix")) == .leaveOn(reason: "TV is showing an app"))
        #expect(decision(foreground: .unknown) == .leaveOn(reason: "what the TV is showing is not known"))
    }

    @Test("someone at the Mac always interrupts a refresh")
    func presenceWins() {
        for trigger in [PowerPolicy.Trigger.screenUnlock, .menuOpened, .appActivated, .userRequested] {
            #expect(PanelCarePolicy.wakeDecision(trigger: trigger, userIdleSeconds: 3_600) == .proceed)
        }
        #expect(PanelCarePolicy.wakeDecision(trigger: .screenWake, userIdleSeconds: 2) == .proceed)
        #expect(PanelCarePolicy.wakeDecision(trigger: .systemWake, userIdleSeconds: 29) == .proceed)
    }

    @Test("a wake with nobody there waits for the refresh")
    func unattendedWakeWaits() {
        #expect(PanelCarePolicy.wakeDecision(trigger: .systemWake, userIdleSeconds: 600) == .hold)
        #expect(PanelCarePolicy.wakeDecision(trigger: .screenWake, userIdleSeconds: 30) == .hold)
    }
}

@Suite("PanelCareSchedule")
struct PanelCareScheduleTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: hour, minute: minute))!
    }

    @Test("without set hours every time of day is allowed")
    func unrestricted() {
        let schedule = PanelCareSchedule()
        #expect(schedule.allows(minuteOfDay: 0))
        #expect(schedule.allows(minuteOfDay: 14 * 60))
        #expect(schedule.nextStart(after: date(12, 0), calendar: calendar) == nil)
    }

    @Test("set hours include their start and exclude their end")
    func daytimeRange() {
        let schedule = PanelCareSchedule(limitsToHours: true, startMinute: 60, endMinute: 360)
        #expect(!schedule.allows(minuteOfDay: 59))
        #expect(schedule.allows(minuteOfDay: 60))
        #expect(schedule.allows(minuteOfDay: 359))
        #expect(!schedule.allows(minuteOfDay: 360))
        #expect(schedule.allows(date(3, 30), calendar: calendar))
        #expect(!schedule.allows(date(15, 0), calendar: calendar))
    }

    @Test("set hours can run past midnight")
    func overnightRange() {
        let schedule = PanelCareSchedule(limitsToHours: true, startMinute: 23 * 60, endMinute: 5 * 60)
        #expect(schedule.allows(minuteOfDay: 23 * 60 + 30))
        #expect(schedule.allows(minuteOfDay: 2 * 60))
        #expect(!schedule.allows(minuteOfDay: 5 * 60))
        #expect(!schedule.allows(minuteOfDay: 12 * 60))
    }

    @Test("equal ends mean the whole day")
    func degenerateRange() {
        let schedule = PanelCareSchedule(limitsToHours: true, startMinute: 120, endMinute: 120)
        #expect(schedule.allows(minuteOfDay: 700))
        #expect(schedule.nextStart(after: date(12, 0), calendar: calendar) == nil)
    }

    @Test("the next start is later today, or tomorrow once today's has passed")
    func nextStart() {
        let schedule = PanelCareSchedule(limitsToHours: true, startMinute: 60, endMinute: 360)
        #expect(schedule.nextStart(after: date(0, 30), calendar: calendar) == date(1, 0))
        #expect(schedule.nextStart(after: date(12, 0), calendar: calendar) == date(1, 0).addingTimeInterval(86_400))
    }

    @Test("a configuration saved before set hours existed loads without them")
    func decodesOlderConfiguration() throws {
        let encoded = try JSONEncoder().encode(TVConfiguration(name: "TV", ipAddress: "192.168.1.2", macAddress: "AA:BB:CC:DD:EE:FF"))
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "panelCareSchedule")
        let decoded = try JSONDecoder().decode(TVConfiguration.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded.panelCareSchedule == PanelCareSchedule())
    }
}

@Suite("PanelCareHistory")
struct PanelCareHistoryTests {
    private let seenAt = Date(timeIntervalSince1970: 1_800_000_000)

    private func reading(hours: Int, count: Int, due: Bool = false) -> PanelCareStatus {
        PanelCareStatus(panelHours: hours, refreshCount: count, longRefreshCount: 11, isRefreshDue: due, refreshIntervalHours: 4)
    }

    @Test("the first reading is a baseline, not a refresh")
    func baseline() {
        let history = PanelCareHistory.updated(nil, with: reading(hours: 6146, count: 425), at: seenAt)
        #expect(history == PanelCareHistory(refreshCount: 425))
        #expect(history.hoursOfUseSinceLastRefresh(reading(hours: 6150, count: 425)) == nil)
    }

    @Test("a count that went up records the refresh, and use is measured from it")
    func refreshSeen() {
        let baseline = PanelCareHistory(refreshCount: 425)
        let history = PanelCareHistory.updated(baseline, with: reading(hours: 6146, count: 426), at: seenAt)
        #expect(history.lastRefresh == .init(panelHours: 6146, observedAt: seenAt))
        #expect(history.hoursOfUseSinceLastRefresh(reading(hours: 6149, count: 426)) == 3)
    }

    @Test("an unchanged count leaves the record alone")
    func unchanged() {
        let history = PanelCareHistory(refreshCount: 426, lastRefresh: .init(panelHours: 6146, observedAt: seenAt))
        #expect(PanelCareHistory.updated(history, with: reading(hours: 6150, count: 426), at: seenAt.addingTimeInterval(3_600)) == history)
    }

    @Test("a count that went down starts again")
    func differentTV() {
        let history = PanelCareHistory(refreshCount: 426, lastRefresh: .init(panelHours: 6146, observedAt: seenAt))
        #expect(PanelCareHistory.updated(history, with: reading(hours: 12, count: 3), at: seenAt) == PanelCareHistory(refreshCount: 3))
    }

    @Test("the readout says when the last refresh was and how far off the next is")
    func presentation() {
        let history = PanelCareHistory(refreshCount: 426, lastRefresh: .init(panelHours: 6146, observedAt: seenAt))
        let soon = PanelCarePresentation(status: reading(hours: 6147, count: 426), history: history, now: seenAt.addingTimeInterval(7_200))
        #expect(soon.useSinceLastRefresh == "1 hour")
        #expect(soon.nextRefresh == "After about 3 hours more of use")
        #expect(soon.tvSchedule == "After every 4 hours of use, once the TV is off")
        #expect(soon.lastRefresh.contains("2 hours"))

        // The TV's flag wins over the estimate in both directions.
        #expect(PanelCarePresentation(status: reading(hours: 6147, count: 426, due: true), history: history).nextRefresh == "Due now")
        #expect(PanelCarePresentation(status: reading(hours: 6155, count: 426), history: history).nextRefresh == "Soon")
    }

    @Test("before the app has seen a refresh it says so instead of guessing")
    func presentationWithoutHistory() {
        let unseen = PanelCarePresentation(status: reading(hours: 6147, count: 426), history: PanelCareHistory(refreshCount: 426))
        #expect(unseen.lastRefresh == "Not seen by this app yet")
        #expect(unseen.useSinceLastRefresh == nil)
        #expect(unseen.nextRefresh == "Not due yet")
    }
}

@Suite("TVController panel care and privileged calls")
@MainActor
struct TVControllerPanelCareTests {
    private final class Idle { var seconds: TimeInterval = 0 }
    private final class LockState { var isLocked: Bool? }
    private final class HistoryStore: PanelCareHistoryStoring {
        var saved: PanelCareHistory?
        func load() -> PanelCareHistory? { saved }
        func save(_ history: PanelCareHistory?) { saved = history }
    }

    private struct Harness {
        let controller: TVController
        let webOS: MockWebOSClient
        let wol: MockWOLService
        let power: MockPowerManager
        let shell: FakeRootShell
        let idle: Idle
        let lock: LockState
        let diagnostics: MockDiagnosticLogger
        let history: HistoryStore
    }

    private func makeHarness(
        refreshDue: Bool = true,
        rooted: Bool = true,
        panelCare: Bool = true,
        systemSaysLocked: Bool? = nil,
        schedule: PanelCareSchedule = PanelCareSchedule(),
        wakeWithMac: Bool = true,
        now: @escaping @MainActor () -> Date = { Date() }
    ) throws -> Harness {
        let history = HistoryStore()
        let webOS = MockWebOSClient()
        let wol = MockWOLService()
        let power = MockPowerManager()
        let shell = FakeRootShell()
        let idle = Idle()
        let lock = LockState()
        lock.isLocked = systemSaysLocked
        let diagnostics = MockDiagnosticLogger()
        let keychain = MockKeychainManager()

        shell.setHandler { command in
            if command.contains("getOledPanelUTT") {
                let output = refreshDue ? capturedPanelCareOutput : capturedPanelCareOutput.replacingOccurrences(of: #""isCondition":true"#, with: #""isCondition":false"#)
                return RootShellOutput(output: output, exitStatus: 0)
            }
            if command.contains("getAllInputStatus") {
                return RootShellOutput(output: #"{"returnValue":true,"devices":[{"id":"HDMI_1","label":"HDMI 1","icon":"HDMI_1.png","connected":true}]}"#, exitStatus: 0)
            }
            if command.contains("setDeviceInfo") {
                return RootShellOutput(output: #"{"returnValue":true}"#, exitStatus: 0)
            }
            return RootShellOutput(output: "uid=0\nkernel=5.4\nluna=yes", exitStatus: 0)
        }

        var lockProvider: (@MainActor () -> Bool)?
        if systemSaysLocked != nil {
            lockProvider = { lock.isLocked ?? false }
        }

        let controller = TVController(
            webOSClient: webOS,
            wolService: wol,
            powerManager: power,
            keychainManager: keychain,
            mediaKeyManager: MockMediaKeyManager(),
            launchAtLoginManager: MockLaunchAtLoginManager(),
            diagnosticLogger: diagnostics,
            rootAccess: RootAccessService(keychain: keychain, shells: [.telnet: shell, .ssh: shell]),
            userIdleSeconds: { idle.seconds },
            panelCareGraceDelay: .milliseconds(30),
            panelCarePollInterval: .milliseconds(30),
            panelCareHistoryStore: history,
            now: now,
            isScreenLocked: lockProvider,
            sleepDebounceInterval: 0,
            wakeConnectInitialDelay: .milliseconds(5),
            wakeConnectRetryDelay: .milliseconds(5),
            wakeConnectMaxAttempts: 3
        )

        var config = TVConfiguration(name: "Test TV", ipAddress: "192.168.1.100", macAddress: "AA:BB:CC:DD:EE:FF", preferredInput: "HDMI_1", wakeWithMac: wakeWithMac, sleepWithMac: true)
        config.rootAccess = RootAccessSettings(isEnabled: rooted, transport: .telnet)
        config.refreshPixelsDuringDowntime = panelCare
        config.panelCareSchedule = schedule
        try controller.saveConfiguration(config)
        return Harness(controller: controller, webOS: webOS, wol: wol, power: power, shell: shell, idle: idle, lock: lock, diagnostics: diagnostics, history: history)
    }

    private func powerOffCount(_ webOS: MockWebOSClient) -> Int {
        webOS.sendCommandCalls.filter { if case .powerOff = $0.command { return true }; return false }.count
    }

    private func settle(_ condition: @MainActor () -> Bool) async {
        var polls = 0
        while !condition() && polls < 600 {
            try? await Task.sleep(for: .milliseconds(10))
            polls += 1
        }
    }

    @Test("locking the Mac switches the TV off when a refresh is due")
    func lockPowersOffWhenDue() async throws {
        let harness = try makeHarness()
        try await harness.controller.connect()
        harness.webOS.simulateInputChange(.hdmi1)

        harness.power.simulateScreenLockEvent()
        await settle { harness.controller.pixelRefreshStartedAt != nil }

        #expect(powerOffCount(harness.webOS) == 1)
        #expect(harness.controller.pixelRefreshStartedAt != nil)
        #expect(!harness.controller.connectionState.isConnected)
    }

    @Test("nothing happens when no refresh is due, or the option is off")
    func lockLeavesTVOnWhenNotDue() async throws {
        for harness in [try makeHarness(refreshDue: false), try makeHarness(panelCare: false)] {
            try await harness.controller.connect()
            harness.webOS.simulateInputChange(.hdmi1)

            harness.power.simulateScreenLockEvent()
            try await Task.sleep(for: .milliseconds(300))

            #expect(powerOffCount(harness.webOS) == 0)
            #expect(harness.controller.pixelRefreshStartedAt == nil)
        }
    }

    @Test("a TV on another input is not switched off for a refresh")
    func lockRespectsOtherInput() async throws {
        let harness = try makeHarness()
        try await harness.controller.connect()
        harness.webOS.simulateInputChange(.hdmi3)

        harness.power.simulateScreenLockEvent()
        try await Task.sleep(for: .milliseconds(300))

        #expect(powerOffCount(harness.webOS) == 0)
    }

    @Test("a display that sleeps while the Mac is unlocked never switches the TV off")
    func displaySleepAloneDoesNothing() async throws {
        let harness = try makeHarness()
        try await harness.controller.connect()
        harness.webOS.simulateInputChange(.hdmi1)

        harness.power.simulateScreenSleepEvent()
        try await Task.sleep(for: .milliseconds(300))

        #expect(powerOffCount(harness.webOS) == 0)
        #expect(harness.controller.pixelRefreshStartedAt == nil)
    }

    @Test("a display that sleeps on a locked Mac switches the TV off, with no lock notification")
    func displaySleepOnLockedMac() async throws {
        let harness = try makeHarness(systemSaysLocked: true)
        try await harness.controller.connect()
        harness.webOS.simulateInputChange(.hdmi1)

        harness.power.simulateScreenSleepEvent()
        await settle { harness.controller.pixelRefreshStartedAt != nil }

        #expect(powerOffCount(harness.webOS) == 1)
    }

    @Test("the system's answer wins over a lock notification that is no longer true")
    func systemLockStateWins() async throws {
        let harness = try makeHarness(systemSaysLocked: false)
        try await harness.controller.connect()
        harness.webOS.simulateInputChange(.hdmi1)

        harness.power.simulateScreenLockEvent()
        try await Task.sleep(for: .milliseconds(300))

        #expect(powerOffCount(harness.webOS) == 0)
    }

    @Test("after the TV comes back, the log says whether a refresh ran")
    func refreshOutcomeIsRecorded() async throws {
        let harness = try makeHarness()
        try await harness.controller.connect()
        harness.webOS.simulateInputChange(.hdmi1)
        await settle { harness.controller.panelCare != nil }
        harness.power.simulateScreenLockEvent()
        await settle { harness.controller.pixelRefreshStartedAt != nil }

        harness.shell.setHandler { _ in
            RootShellOutput(output: capturedPanelCareOutput
                .replacingOccurrences(of: #""offrsCount":424"#, with: #""offrsCount":425"#)
                .replacingOccurrences(of: #""isCondition":true"#, with: #""isCondition":false"#), exitStatus: 0)
        }
        await settle { harness.controller.pixelRefreshStartedAt == nil }

        #expect(harness.diagnostics.logCalls.contains { $0.message == "Pixel refresh ran while the TV was off" })
        #expect(harness.controller.panelCare?.refreshCount == 425)
        // Seeing the count go up is also what dates the last refresh.
        #expect(harness.history.saved?.refreshCount == 425)
        #expect(harness.history.saved?.lastRefresh?.panelHours == 6133)
    }

    /// Seen on an LG C2: the TV answered for six minutes into its refresh with the count
    /// unchanged, and the app reported after 30 seconds that no refresh had run.
    @Test("a refresh still in progress is not reported as one that did not run")
    func refreshOutcomeWaitsForTheQuietPeriodToEnd() async throws {
        let harness = try makeHarness()
        try await harness.controller.connect()
        harness.webOS.simulateInputChange(.hdmi1)
        await settle { harness.controller.panelCare != nil }
        harness.power.simulateScreenLockEvent()
        await settle { harness.controller.pixelRefreshStartedAt != nil }

        // Several polls while the TV still reports the old count.
        try await Task.sleep(for: .milliseconds(200))

        #expect(harness.controller.pixelRefreshStartedAt != nil)
        #expect(!harness.diagnostics.logCalls.contains { $0.message == "The TV did not run a pixel refresh while it was off" })
    }

    @Test("a TV switched off for a refresh comes back on unlock even with wake-with-Mac off")
    func unlockRestoresTVWithoutWakePreference() async throws {
        let harness = try makeHarness(wakeWithMac: false)
        try await harness.controller.connect()
        harness.webOS.simulateInputChange(.hdmi1)
        harness.power.simulateScreenLockEvent()
        await settle { harness.controller.pixelRefreshStartedAt != nil }

        harness.power.simulateScreenUnlockEvent()
        await settle { !harness.wol.wakeCalls.isEmpty }

        #expect(harness.wol.wakeCalls.count == 1)
        #expect(harness.controller.pixelRefreshStartedAt == nil)
    }

    @Test("a TV left in standby because nobody was there is woken once someone is")
    func standbyLeftAloneIsWokenWhenSomeoneReturns() async throws {
        let harness = try makeHarness(refreshDue: false)
        try await harness.controller.connect()
        harness.webOS.powerStatusResults = [
            .success(TVPowerStatus(state: "Active Standby")),
            .success(TVPowerStatus(state: "Active Standby")),
            .success(TVPowerStatus(state: "Active"))
        ]
        harness.idle.seconds = 3_600

        harness.power.simulateWakeEvent()
        await harness.controller.wakeRecoveryTask?.value
        #expect(harness.wol.wakeCalls.isEmpty)

        harness.idle.seconds = 1
        await settle { !harness.wol.wakeCalls.isEmpty }
        await harness.controller.wakeRecoveryTask?.value
        #expect(harness.wol.wakeCalls.count == 1)
    }

    private static func time(hour: Int, minute: Int, second: Int = 0) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: second, of: Date())!
    }

    @Test("outside the set hours a locked Mac does not switch the TV off; inside them it does")
    func setHoursAreRespected() async throws {
        let overnight = PanelCareSchedule(limitsToHours: true, startMinute: 60, endMinute: 360)

        let afternoon = try makeHarness(schedule: overnight, now: { Self.time(hour: 15, minute: 0) })
        try await afternoon.controller.connect()
        afternoon.webOS.simulateInputChange(.hdmi1)
        afternoon.power.simulateScreenLockEvent()
        try await Task.sleep(for: .milliseconds(300))
        #expect(powerOffCount(afternoon.webOS) == 0)

        let night = try makeHarness(schedule: overnight, now: { Self.time(hour: 3, minute: 0) })
        try await night.controller.connect()
        night.webOS.simulateInputChange(.hdmi1)
        night.power.simulateScreenLockEvent()
        await settle { night.controller.pixelRefreshStartedAt != nil }
        #expect(powerOffCount(night.webOS) == 1)
    }

    @Test("a Mac locked before the set hours has its TV switched off when they begin, unless it is unlocked first")
    func setHoursBeginWhileLocked() async throws {
        let overnight = PanelCareSchedule(limitsToHours: true, startMinute: 60, endMinute: 360)
        for unlocksFirst in [false, true] {
            // A clock that starts shortly before 01:00 and runs in real time. The unlocking
            // case gets a longer lead so the unlock lands first even on a busy test run.
            let lead: TimeInterval = unlocksFirst ? 3 : 0.4
            let launched = Date()
            let base = Self.time(hour: 1, minute: 0).addingTimeInterval(-lead)
            let harness = try makeHarness(schedule: overnight, now: { base.addingTimeInterval(Date().timeIntervalSince(launched)) })
            try await harness.controller.connect()
            harness.webOS.simulateInputChange(.hdmi1)

            harness.power.simulateScreenLockEvent()
            await settle { harness.diagnostics.logCalls.contains { $0.message == "Waiting for the set hours" } }

            if unlocksFirst {
                harness.power.simulateScreenUnlockEvent()
                try await Task.sleep(for: .seconds(lead + 0.5))
                #expect(powerOffCount(harness.webOS) == 0)
            } else {
                await settle { harness.controller.pixelRefreshStartedAt != nil }
                #expect(powerOffCount(harness.webOS) == 1)
            }
        }
    }

    @Test("panel care is read again when the shell was not up at connect")
    func panelCareRetriesAfterConnect() async throws {
        let harness = try makeHarness()
        harness.shell.setHandler { command in
            if command.contains("getOledPanelUTT") {
                throw RootShellError.connectionFailed("Connection refused")
            }
            return RootShellOutput(output: "uid=0\nkernel=5.4\nluna=yes", exitStatus: 0)
        }
        try await harness.controller.connect()
        try await Task.sleep(for: .milliseconds(100))
        #expect(harness.controller.panelCare == nil)

        harness.shell.setHandler { _ in RootShellOutput(output: capturedPanelCareOutput, exitStatus: 0) }
        #expect(await harness.controller.refreshPanelCare())
        #expect(harness.controller.panelCare?.refreshCount == 424)
    }

    @Test("a lock that ends before the grace period is over never switches the TV off")
    func unlockBeforeDecisionLeavesTVOn() async throws {
        let harness = try makeHarness()
        try await harness.controller.connect()
        harness.webOS.simulateInputChange(.hdmi1)

        harness.power.simulateScreenLockEvent()
        harness.power.simulateScreenUnlockEvent()
        try await Task.sleep(for: .milliseconds(300))

        #expect(powerOffCount(harness.webOS) == 0)
        #expect(harness.controller.pixelRefreshStartedAt == nil)
    }

    @Test("unlocking within the grace period cancels the power-off")
    func quickUnlockCancels() async throws {
        let webOS = MockWebOSClient()
        let power = MockPowerManager()
        let controller = TVController(
            webOSClient: webOS,
            wolService: MockWOLService(),
            powerManager: power,
            keychainManager: MockKeychainManager(),
            mediaKeyManager: MockMediaKeyManager(),
            launchAtLoginManager: MockLaunchAtLoginManager(),
            diagnosticLogger: MockDiagnosticLogger(),
            panelCareGraceDelay: .seconds(30)
        )
        var config = TVConfiguration(name: "Test TV", ipAddress: "192.168.1.100", macAddress: "AA:BB:CC:DD:EE:FF", wakeWithMac: false)
        config.refreshPixelsDuringDowntime = true
        try controller.saveConfiguration(config)
        try await controller.connect()

        power.simulateScreenLockEvent()
        power.simulateScreenUnlockEvent()
        try await Task.sleep(for: .milliseconds(100))

        #expect(powerOffCount(webOS) == 0)
    }

    @Test("an unattended wake during a refresh waits, and the TV wakes when the refresh ends")
    func unattendedWakeIsHeldThenReleased() async throws {
        let harness = try makeHarness()
        try await harness.controller.connect()
        harness.webOS.simulateInputChange(.hdmi1)
        harness.power.simulateScreenLockEvent()
        await settle { harness.controller.pixelRefreshStartedAt != nil }

        harness.idle.seconds = 900
        harness.power.simulateWakeEvent()
        try await Task.sleep(for: .milliseconds(50))
        #expect(harness.wol.wakeCalls.isEmpty)

        // The TV reports the refresh done.
        harness.shell.setHandler { _ in
            RootShellOutput(output: capturedPanelCareOutput.replacingOccurrences(of: #""isCondition":true"#, with: #""isCondition":false"#), exitStatus: 0)
        }
        await settle { harness.wol.wakeCalls.count == 1 }

        #expect(harness.controller.pixelRefreshStartedAt == nil)
        #expect(harness.wol.wakeCalls.count == 1)
    }

    @Test("someone unlocking the Mac gets the TV back straight away")
    func unlockInterruptsRefresh() async throws {
        let harness = try makeHarness()
        try await harness.controller.connect()
        harness.webOS.simulateInputChange(.hdmi1)
        harness.power.simulateScreenLockEvent()
        await settle { harness.controller.pixelRefreshStartedAt != nil }

        harness.idle.seconds = 900
        harness.power.simulateScreenUnlockEvent()
        await harness.controller.wakeRecoveryTask?.value

        #expect(harness.wol.wakeCalls.count == 1)
        #expect(harness.controller.pixelRefreshStartedAt == nil)
    }

    @Test("the PC label goes through the root shell when the pairing connection refuses it")
    func pcLabelUsesPrivilegedCall() async throws {
        let harness = try makeHarness()
        try await harness.controller.connect()
        harness.webOS.commandErrors = [.setDeviceInfo: LGTVError.commandFailed("401 insufficient permissions")]

        try await harness.controller.setPCMode(for: .hdmi1, enabled: true)

        let call = try #require(harness.shell.calls.last { $0.command.contains("setDeviceInfo") })
        #expect(call.command.contains(#""icon":"pc.png""#))
        #expect(call.command.contains(#""id":"HDMI_1""#))
        #expect(await harness.controller.isPCMode(inputID: "HDMI_1") != nil)
    }

    @Test("without root, the PC label goes through the TV's notification service")
    func pcLabelWithoutRoot() async throws {
        let harness = try makeHarness(rooted: false)
        try await harness.controller.connect()
        harness.webOS.commandErrors = [.setDeviceInfo: LGTVError.commandFailed("401 insufficient permissions")]
        harness.webOS.requestReplies["ssap://system.notifications/createAlert"] = .success(SSAPReply(payload: ["alertId": "a1", "returnValue": true]))

        try await harness.controller.setPCMode(for: .hdmi1, enabled: true)

        #expect(harness.webOS.requestCalls.map(\.uri) == ["ssap://system.notifications/createAlert", "ssap://system.notifications/closeAlert"])
        #expect(harness.shell.calls.isEmpty)
    }

    @Test("the input list comes from the root shell when the pairing connection has none")
    func inputListFromRoot() async throws {
        let harness = try makeHarness()
        try await harness.controller.connect()

        #expect(await harness.controller.isPCMode(inputID: "HDMI_1") == false)
        #expect(harness.controller.capabilities?.inputs.map(\.id) == ["HDMI_1"])
    }

    @Test("an unknown PC label is not written blind after a wake")
    func unknownPCLabelIsNotWritten() async throws {
        let webOS = MockWebOSClient()
        let controller = TVController(
            webOSClient: webOS,
            wolService: MockWOLService(),
            powerManager: MockPowerManager(),
            keychainManager: MockKeychainManager(),
            mediaKeyManager: MockMediaKeyManager(),
            launchAtLoginManager: MockLaunchAtLoginManager(),
            diagnosticLogger: MockDiagnosticLogger(),
            wakeConnectInitialDelay: .milliseconds(5),
            wakeConnectRetryDelay: .milliseconds(5),
            wakeConnectMaxAttempts: 3
        )
        try controller.saveConfiguration(TVConfiguration(name: "Test TV", ipAddress: "192.168.1.100", macAddress: "AA:BB:CC:DD:EE:FF", wakeWithMac: true, enablePCMode: true))

        await controller.ensureTVAwake(reason: "systemWake")

        #expect(!webOS.sendCommandCalls.contains { if case .setDeviceInfo = $0.command { return true }; return false })
    }
}
