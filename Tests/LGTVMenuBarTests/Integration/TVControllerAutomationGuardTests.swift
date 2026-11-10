import Testing
import Foundation
@testable import LGTVMenuBar

/// Loop guards and "do not disturb the viewer" rules in the controller.
@Suite("TVController automation guards")
@MainActor
struct TVControllerAutomationGuardTests {

    private struct Harness {
        let controller: TVController
        let webOS: MockWebOSClient
        let wol: MockWOLService
        let power: MockPowerManager
        let mediaKeys: MockMediaKeyManager
        let diagnostics: MockDiagnosticLogger
    }

    private func makeHarness(reachable: Bool?, config: TVConfiguration) throws -> Harness {
        let webOS = MockWebOSClient()
        let wol = MockWOLService()
        let power = MockPowerManager()
        let mediaKeys = MockMediaKeyManager()
        let diagnostics = MockDiagnosticLogger()
        let controller = TVController(
            webOSClient: webOS,
            wolService: wol,
            powerManager: power,
            keychainManager: MockKeychainManager(),
            mediaKeyManager: mediaKeys,
            launchAtLoginManager: MockLaunchAtLoginManager(),
            diagnosticLogger: diagnostics,
            reachabilityProbe: reachable.map { StubReachabilityProbe(reachable: $0) },
            sleepDebounceInterval: 0,
            wakeConnectInitialDelay: .milliseconds(5),
            wakeConnectRetryDelay: .milliseconds(5),
            wakeConnectMaxAttempts: 3
        )
        try controller.saveConfiguration(config)
        return Harness(controller: controller, webOS: webOS, wol: wol, power: power, mediaKeys: mediaKeys, diagnostics: diagnostics)
    }

    private func config(switchInputOnWake: Bool = true, wakeOnMenuOpen: Bool = true) -> TVConfiguration {
        TVConfiguration(
            name: "Test TV", ipAddress: "192.168.1.100", macAddress: "AA:BB:CC:DD:EE:FF", preferredInput: "HDMI_1",
            wakeWithMac: true, sleepWithMac: true, switchInputOnWake: switchInputOnWake, wakeOnMenuOpen: wakeOnMenuOpen
        )
    }

    private func count(_ webOS: MockWebOSClient, _ matches: (WebOSCommand) -> Bool) -> Int {
        webOS.sendCommandCalls.filter { matches($0.command) }.count
    }

    private func isSetInput(_ command: WebOSCommand) -> Bool {
        if case .setInput = command { return true }
        return false
    }

    private func isPowerOff(_ command: WebOSCommand) -> Bool {
        if case .powerOff = command { return true }
        return false
    }

    @Test("reconnecting to a TV that was already on does not switch its input")
    func noInputHijackWhenTVAlreadyOn() async throws {
        let harness = try makeHarness(reachable: true, config: config())
        harness.webOS.mockPowerStatus = TVPowerStatus(state: "Active")

        await harness.controller.ensureTVAwake(reason: "systemWake")

        #expect(harness.controller.connectionState.isConnected)
        #expect(count(harness.webOS, isSetInput) == 0)
        #expect(harness.wol.wakeCalls.isEmpty)
    }

    @Test("background reconnect lets go of a TV that turns out to be in standby")
    func supervisionReleasesStandbyTV() async throws {
        let harness = try makeHarness(reachable: true, config: config())
        try await harness.controller.connect()
        harness.webOS.mockPowerStatus = TVPowerStatus(state: "Active Standby")

        harness.webOS.simulateConnectionStateChange(to: .error(MockWebOSClientError.timeout))
        var polls = 0
        while harness.webOS.connectCallCount < 2 && polls < 400 {
            try await Task.sleep(for: .milliseconds(50))
            polls += 1
        }
        try await Task.sleep(for: .milliseconds(200))

        #expect(harness.webOS.connectCallCount == 2)
        #expect(!harness.controller.connectionState.isConnected)
        #expect(harness.wol.wakeCalls.isEmpty)
    }

    @Test("a TV answering in standby is still sent a wake")
    func standbyTVIsWoken() async throws {
        let harness = try makeHarness(reachable: true, config: config())
        harness.webOS.powerStatusResults = [
            .success(TVPowerStatus(state: "Active Standby")),
            .success(TVPowerStatus(state: "Active"))
        ]

        await harness.controller.ensureTVAwake(reason: "systemWake")

        #expect(harness.wol.wakeCalls.count == 1)
        #expect(count(harness.webOS, isSetInput) == 1)
    }

    @Test("a screen-on the TV declines does not stop the input switch after a wake")
    func declinedScreenOnStillRunsPostWakeActions() async throws {
        let harness = try makeHarness(reachable: false, config: config())
        harness.webOS.mockPowerStatus = TVPowerStatus(state: "Mystery State")
        harness.webOS.commandErrors = [.screenOn: LGTVError.commandFailed("already on")]

        await harness.controller.ensureTVAwake(reason: "systemWake")

        #expect(count(harness.webOS, isSetInput) == 1)
    }

    @Test("Disconnect stays disconnected until the user or a trigger reconnects")
    func userDisconnectIsNotUndone() async throws {
        let harness = try makeHarness(reachable: true, config: config())
        try await harness.controller.connect()

        harness.controller.disconnect()
        try await Task.sleep(for: .seconds(3))
        #expect(harness.webOS.connectCallCount == 1)
        #expect(harness.controller.connectionState.isDisconnected)

        await harness.controller.handleAutomationTrigger(.appActivated)?.value
        #expect(harness.controller.connectionState.isConnected)
    }

    @Test("the screensaver does not stop the TV being switched off with the Mac")
    func screensaverDoesNotBlockSleep() async throws {
        let harness = try makeHarness(reachable: nil, config: config())
        try await harness.controller.connect()
        harness.webOS.simulateInputChange(.hdmi1)
        if let ignored = TVForeground.from(appId: "com.webos.app.screensaver") {
            harness.webOS.simulateForegroundChange(ignored)
        }

        harness.power.simulateSleepEvent()
        try await Task.sleep(for: .milliseconds(50))

        #expect(count(harness.webOS, isPowerOff) == 1)
    }

    @Test("mute state follows the request even when the TV's update arrives first")
    func muteStateIsNotInverted() async throws {
        let harness = try makeHarness(reachable: nil, config: config())
        #if LOCAL_ARYLIC_BUILD
        // Other suites persist Arylic routing in the shared defaults; this test is about the TV.
        harness.controller.isArylicVolumeControlEnabled = false
        #endif
        try await harness.controller.connect()
        harness.webOS.onSendCommand = { [weak webOS = harness.webOS] command in
            if case .mute = command { webOS?.simulateVolumeChange(volume: 10, isMuted: true) }
        }

        try await harness.controller.toggleMute()
        try await Task.sleep(for: .milliseconds(20))

        #expect(harness.controller.isMuted)
    }

    @Test("a TV the app powered on is switched to the Mac's input")
    func switchesInputAfterPoweringOn() async throws {
        let harness = try makeHarness(reachable: false, config: config())
        harness.webOS.mockPowerStatus = TVPowerStatus(state: "Active")

        await harness.controller.ensureTVAwake(reason: "systemWake")

        #expect(count(harness.webOS, isSetInput) == 1)
        #expect(harness.controller.foreground == .input(.hdmi1))
    }

    @Test("Mac sleep leaves the TV on when an app is in front")
    func sleepLeavesStreamingAppAlone() async throws {
        let harness = try makeHarness(reachable: nil, config: config())
        try await harness.controller.connect()
        harness.webOS.simulateInputChange(.hdmi1)
        harness.webOS.simulateForegroundChange(.app("netflix"))

        harness.power.simulateSleepEvent()
        try await Task.sleep(for: .milliseconds(50))

        #expect(harness.controller.currentInput == nil)
        #expect(count(harness.webOS, isPowerOff) == 0)
    }

    @Test("Mac sleep asks the TV what is in front before powering it off")
    func sleepUsesFreshForeground() async throws {
        let harness = try makeHarness(reachable: nil, config: config())
        try await harness.controller.connect()
        harness.webOS.simulateInputChange(.hdmi1)
        harness.webOS.foregroundOnQuery = .input(.hdmi3)

        harness.power.simulateSleepEvent()
        try await Task.sleep(for: .milliseconds(50))

        #expect(count(harness.webOS, isPowerOff) == 0)
    }

    @Test("Mac sleep powers the TV off when the Mac's input is in front")
    func sleepPowersOffOnPreferredInput() async throws {
        let harness = try makeHarness(reachable: nil, config: config())
        try await harness.controller.connect()
        harness.webOS.simulateInputChange(.hdmi1)

        harness.power.simulateSleepEvent()
        try await Task.sleep(for: .milliseconds(50))

        #expect(count(harness.webOS, isPowerOff) == 1)
    }

    @Test("a refused pairing stops automatic connects until the user connects")
    func pairingRefusalStopsRetries() async throws {
        let harness = try makeHarness(reachable: false, config: config())
        harness.webOS.connectResults = [.failure(LGTVError.pairingRejected)]
        harness.webOS.connectionStateAfterConnectFailure = .disconnected

        await harness.controller.ensureTVAwake(reason: "systemWake")
        #expect(harness.webOS.connectCallCount == 1)
        #expect(harness.controller.pairingRequiresUser)

        await harness.controller.ensureTVAwake(reason: "screenUnlock")
        #expect(harness.webOS.connectCallCount == 1)
        #expect(harness.wol.wakeCalls.count == 1)

        try await harness.controller.connect()
        #expect(!harness.controller.pairingRequiresUser)
        #expect(harness.controller.connectionState.isConnected)
    }

    @Test("repeated automatic wakes trip the governor instead of looping")
    func governorStopsWakeLoop() async throws {
        let harness = try makeHarness(reachable: false, config: config(switchInputOnWake: false))
        harness.webOS.mockPowerStatus = TVPowerStatus(state: "Active")

        for _ in 0..<8 {
            await harness.controller.ensureTVAwake(reason: "systemWake")
            harness.controller.disconnect()
        }

        #expect(harness.wol.wakeCalls.count == 6)
        #expect(harness.controller.suspendedAutomation == [.powerOn])

        harness.controller.resetSuspendedAutomation()
        await harness.controller.ensureTVAwake(reason: "systemWake")
        #expect(harness.wol.wakeCalls.count == 7)
    }

    @Test("Mac sleep cancels a wake recovery that is still retrying")
    func sleepCancelsWakeRecovery() async throws {
        let webOS = MockWebOSClient()
        let wol = MockWOLService()
        let power = MockPowerManager()
        let controller = TVController(
            webOSClient: webOS,
            wolService: wol,
            powerManager: power,
            keychainManager: MockKeychainManager(),
            mediaKeyManager: MockMediaKeyManager(),
            launchAtLoginManager: MockLaunchAtLoginManager(),
            diagnosticLogger: MockDiagnosticLogger(),
            sleepDebounceInterval: 0,
            wakeConnectInitialDelay: .milliseconds(5),
            wakeConnectRetryDelay: .milliseconds(100),
            wakeConnectMaxAttempts: 200,
            wakeConnectTimeout: .seconds(20)
        )
        try controller.saveConfiguration(config())
        webOS.shouldThrowOnConnect = true

        power.simulateWakeEvent()
        // Counted in iterations, not wall-clock time: other suites can hold the main actor for
        // seconds at a time when the whole test target runs in parallel.
        var polls = 0
        while webOS.connectCallCount < 1 && polls < 3_000 {
            try await Task.sleep(for: .milliseconds(10))
            polls += 1
        }
        #expect(webOS.connectCallCount >= 1)

        power.simulateSleepEvent()
        await controller.wakeRecoveryTask?.value
        let attemptsAtCancellation = webOS.connectCallCount
        try await Task.sleep(for: .milliseconds(400))

        #expect(webOS.connectCallCount == attemptsAtCancellation)
        #expect(attemptsAtCancellation < 200)
    }

    @Test("opening the menu reconnects without waking when the option is off")
    func menuOpenWithoutWake() async throws {
        let harness = try makeHarness(reachable: true, config: config(wakeOnMenuOpen: false))

        await harness.controller.handleAutomationTrigger(.menuOpened)?.value

        #expect(harness.wol.wakeCalls.isEmpty)
        #expect(harness.controller.connectionState.isConnected)
    }

    @Test("opening the menu does nothing to a TV that is off when the option is off")
    func menuOpenLeavesOffTVAlone() async throws {
        let harness = try makeHarness(reachable: false, config: config(wakeOnMenuOpen: false))

        await harness.controller.handleAutomationTrigger(.menuOpened)?.value

        #expect(harness.wol.wakeCalls.isEmpty)
        #expect(harness.webOS.connectCallCount == 0)
    }

    @Test("activating the app never sends a wake")
    func appActivationNeverWakes() async throws {
        let harness = try makeHarness(reachable: false, config: config())

        await harness.controller.handleAutomationTrigger(.appActivated)?.value

        #expect(harness.wol.wakeCalls.isEmpty)
    }

    @Test("a lost connection is re-established once the TV is reachable")
    func reconnectsAfterDrop() async throws {
        let harness = try makeHarness(reachable: true, config: config())
        try await harness.controller.connect()
        #expect(harness.webOS.connectCallCount == 1)

        harness.webOS.simulateConnectionStateChange(to: .error(MockWebOSClientError.timeout))
        var polls = 0
        while harness.webOS.connectCallCount < 2 && polls < 400 {
            try await Task.sleep(for: .milliseconds(50))
            polls += 1
        }

        #expect(harness.webOS.connectCallCount == 2)
        #expect(harness.controller.connectionState.isConnected)
        #expect(harness.wol.wakeCalls.isEmpty)
    }

    @Test("missing Accessibility permission keeps the media key preference")
    func mediaKeyPreferenceSurvivesMissingPermission() async throws {
        let harness = try makeHarness(reachable: nil, config: config())
        harness.mediaKeys.mockHasAccessibilityPermission = false
        harness.controller.isMediaKeyControlEnabled = true
        try await harness.controller.connect()
        try await Task.sleep(for: .milliseconds(50))

        #expect(harness.controller.isMediaKeyControlEnabled)
        #expect(harness.controller.isMediaKeyPermissionMissing)
        UserDefaults.standard.removeObject(forKey: "isMediaKeyControlEnabled")
    }

    @Test("configuration updates change only the fields they touch")
    func updateConfigurationIsFieldLocal() throws {
        var initial = config()
        initial.displayLock = DisplayLockProfile(isEnabled: true, hdrEnabled: true)
        let harness = try makeHarness(reachable: nil, config: initial)

        try harness.controller.updateConfiguration { $0.name = "Renamed" }

        #expect(harness.controller.configuration?.name == "Renamed")
        #expect(harness.controller.configuration?.displayLock == initial.displayLock)
        #expect(harness.controller.configuration?.id == initial.id)
    }
}
