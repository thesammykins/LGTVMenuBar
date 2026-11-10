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
    PanelCareStatus(panelHours: 100, shortRefreshLastHours: due ? 90 : 99, shortRefreshIntervalHours: 4, shortRefreshCount: 1, longRefreshLastHours: 0, longRefreshIntervalHours: 500, longRefreshCount: 0, isRefreshDue: due)
}

@Suite("PanelCareStatus")
struct PanelCareStatusTests {
    @Test("the TV's replies are parsed into hours and due flags")
    func parseCaptured() throws {
        let status = try #require(PanelCareStatus.parse(capturedPanelCareOutput))
        #expect(status.panelHours == 6133)
        #expect(status.hoursSinceShortRefresh == 114)
        #expect(status.shortRefreshIntervalHours == 4)
        #expect(status.shortRefreshOverdueHours == 110)
        #expect(status.shortRefreshCount == 424)
        #expect(status.hoursSinceLongRefresh == 541)
        #expect(status.isLongRefreshDue)
        #expect(status.isRefreshDue)
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
    private func decision(enabled: Bool = true, locked: Bool = true, status: PanelCareStatus? = status(due: true), connected: Bool = true, foreground: TVForeground = .input(.hdmi1)) -> PanelCarePolicy.PowerOffDecision {
        PanelCarePolicy.powerOffDecision(isEnabled: enabled, isMacLocked: locked, status: status, isConnected: connected, foreground: foreground, preferredInput: "HDMI_1")
    }

    @Test("the TV is switched off only when a refresh is due and the Mac's input is in front")
    func powerOff() {
        #expect(decision() == .powerOff)
        #expect(decision(enabled: false) == .leaveOn(reason: "panel care is off"))
        #expect(decision(locked: false) == .leaveOn(reason: "the Mac is not locked"))
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

@Suite("TVController panel care and privileged calls")
@MainActor
struct TVControllerPanelCareTests {
    private final class Idle { var seconds: TimeInterval = 0 }

    private struct Harness {
        let controller: TVController
        let webOS: MockWebOSClient
        let wol: MockWOLService
        let power: MockPowerManager
        let shell: FakeRootShell
        let idle: Idle
    }

    private func makeHarness(refreshDue: Bool = true, rooted: Bool = true, panelCare: Bool = true) throws -> Harness {
        let webOS = MockWebOSClient()
        let wol = MockWOLService()
        let power = MockPowerManager()
        let shell = FakeRootShell()
        let idle = Idle()
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

        let controller = TVController(
            webOSClient: webOS,
            wolService: wol,
            powerManager: power,
            keychainManager: keychain,
            mediaKeyManager: MockMediaKeyManager(),
            launchAtLoginManager: MockLaunchAtLoginManager(),
            diagnosticLogger: MockDiagnosticLogger(),
            rootAccess: RootAccessService(keychain: keychain, shells: [.telnet: shell, .ssh: shell]),
            userIdleSeconds: { idle.seconds },
            panelCareGraceDelay: .milliseconds(30),
            panelCarePollInterval: .milliseconds(30),
            sleepDebounceInterval: 0,
            wakeConnectInitialDelay: .milliseconds(5),
            wakeConnectRetryDelay: .milliseconds(5),
            wakeConnectMaxAttempts: 3
        )

        var config = TVConfiguration(name: "Test TV", ipAddress: "192.168.1.100", macAddress: "AA:BB:CC:DD:EE:FF", preferredInput: "HDMI_1", wakeWithMac: true, sleepWithMac: true)
        config.rootAccess = RootAccessSettings(isEnabled: rooted, transport: .telnet)
        config.refreshPixelsDuringDowntime = panelCare
        try controller.saveConfiguration(config)
        return Harness(controller: controller, webOS: webOS, wol: wol, power: power, shell: shell, idle: idle)
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
