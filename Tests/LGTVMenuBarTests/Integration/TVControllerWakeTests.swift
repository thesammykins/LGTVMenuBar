import Testing
import Foundation
@testable import LGTVMenuBar

@Suite("TV Controller Wake/Sleep Integration Tests")
@MainActor
struct TVControllerWakeTests {

    private func waitUntil(
        timeout: Duration = .seconds(1),
        pollInterval: Duration = .milliseconds(10),
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        let deadline = ContinuousClock.now + timeout
        while !condition() && ContinuousClock.now < deadline {
            try? await Task.sleep(for: pollInterval)
        }
    }

    @Test("system wake triggers WOL and reconnect")
    func systemWakeTriggersWakeFlow() async throws {
        let mockPowerManager = MockPowerManager()
        let mockWebOS = MockWebOSClient()
        let mockWOL = MockWOLService()
        let mockKeychain = MockKeychainManager()
        let mockMediaKey = MockMediaKeyManager()
        let mockLaunch = MockLaunchAtLoginManager()
        let mockDiagnostic = MockDiagnosticLogger()

        let controller = TVController(
            webOSClient: mockWebOS,
            wolService: mockWOL,
            powerManager: mockPowerManager,
            keychainManager: mockKeychain,
            mediaKeyManager: mockMediaKey,
            launchAtLoginManager: mockLaunch,
            diagnosticLogger: mockDiagnostic,
            wakeConnectInitialDelay: .milliseconds(10),
            wakeConnectRetryDelay: .milliseconds(10),
            wakeConnectMaxAttempts: 3
        )

        let config = TVConfiguration(
            name: "Test TV",
            ipAddress: "192.168.1.100",
            macAddress: "AA:BB:CC:DD:EE:FF",
            wakeWithMac: true
        )
        try controller.saveConfiguration(config)

        mockPowerManager.simulateWakeEvent()

        await waitUntil {
            mockWebOS.connectCallCount == 1 &&
            mockWOL.wakeCalls.count == 1 &&
            mockWebOS.sendCommandCalls.contains { if case .screenOn = $0.command { return true }; return false }
        }

        #expect(mockWOL.wakeCalls.count == 1)
        #expect(mockWebOS.connectCallCount == 1)
        #expect(mockWebOS.sendCommandCalls.contains { if case .screenOn = $0.command { return true }; return false })
    }

    @Test("screen wake does not trigger full wake flow")
    func screenWakeDoesNotTriggerWakeFlow() async throws {
        let mockPowerManager = MockPowerManager()
        let mockWebOS = MockWebOSClient()
        let mockWOL = MockWOLService()
        let mockKeychain = MockKeychainManager()
        let mockMediaKey = MockMediaKeyManager()
        let mockLaunch = MockLaunchAtLoginManager()
        let mockDiagnostic = MockDiagnosticLogger()

        let controller = TVController(
            webOSClient: mockWebOS,
            wolService: mockWOL,
            powerManager: mockPowerManager,
            keychainManager: mockKeychain,
            mediaKeyManager: mockMediaKey,
            launchAtLoginManager: mockLaunch,
            diagnosticLogger: mockDiagnostic,
            wakeConnectInitialDelay: .milliseconds(10),
            wakeConnectRetryDelay: .milliseconds(10),
            wakeConnectMaxAttempts: 3
        )

        let config = TVConfiguration(
            name: "Test TV",
            ipAddress: "192.168.1.100",
            macAddress: "AA:BB:CC:DD:EE:FF",
            wakeWithMac: true
        )
        try controller.saveConfiguration(config)

        mockPowerManager.simulateScreenWakeEvent()
        mockPowerManager.simulateScreenUnlockEvent()
        try await Task.sleep(for: .milliseconds(50))

        #expect(mockWOL.wakeCalls.isEmpty)
        #expect(mockWebOS.connectCallCount == 0)
    }

    @Test("failed wake attempt does not debounce the next wake event")
    func failedWakeAttemptDoesNotDebounceNextWake() async throws {
        let mockPowerManager = MockPowerManager()
        let mockWebOS = MockWebOSClient()
        let mockWOL = MockWOLService()
        let mockKeychain = MockKeychainManager()
        let mockMediaKey = MockMediaKeyManager()
        let mockLaunch = MockLaunchAtLoginManager()
        let mockDiagnostic = MockDiagnosticLogger()

        mockWebOS.connectResults = [
            .failure(MockWebOSClientError.connectionFailed("First attempt failed")),
            .failure(MockWebOSClientError.connectionFailed("First attempt failed")),
            .failure(MockWebOSClientError.connectionFailed("First attempt failed")),
            .success(())
        ]

        let controller = TVController(
            webOSClient: mockWebOS,
            wolService: mockWOL,
            powerManager: mockPowerManager,
            keychainManager: mockKeychain,
            mediaKeyManager: mockMediaKey,
            launchAtLoginManager: mockLaunch,
            diagnosticLogger: mockDiagnostic,
            wakeConnectInitialDelay: .milliseconds(10),
            wakeConnectRetryDelay: .milliseconds(10),
            wakeConnectMaxAttempts: 3
        )

        let config = TVConfiguration(
            name: "Test TV",
            ipAddress: "192.168.1.100",
            macAddress: "AA:BB:CC:DD:EE:FF",
            wakeWithMac: true
        )
        try controller.saveConfiguration(config)

        mockPowerManager.simulateWakeEvent()

        await waitUntil {
            mockWebOS.connectCallCount == 3
        }

        let wakeCallsAfterFailure = mockWOL.wakeCalls.count
        let connectCallsAfterFailure = mockWebOS.connectCallCount

        mockPowerManager.simulateWakeEvent()

        await waitUntil {
            mockWebOS.connectCallCount == 4
        }

        #expect(wakeCallsAfterFailure == 1)
        #expect(connectCallsAfterFailure == 3)
        #expect(mockWOL.wakeCalls.count == 2)
        #expect(mockWebOS.connectCallCount == 4)
        #expect(controller.connectionState == .connected)
    }

    @Test("wake flow retries connect until TV becomes reachable")
    func wakeFlowRetriesConnect() async throws {
        let mockPowerManager = MockPowerManager()
        let mockWebOS = MockWebOSClient()
        let mockWOL = MockWOLService()
        let mockKeychain = MockKeychainManager()
        let mockMediaKey = MockMediaKeyManager()
        let mockLaunch = MockLaunchAtLoginManager()
        let mockDiagnostic = MockDiagnosticLogger()

        mockWebOS.connectResults = [
            .failure(MockWebOSClientError.timeout),
            .success(())
        ]

        let controller = TVController(
            webOSClient: mockWebOS,
            wolService: mockWOL,
            powerManager: mockPowerManager,
            keychainManager: mockKeychain,
            mediaKeyManager: mockMediaKey,
            launchAtLoginManager: mockLaunch,
            diagnosticLogger: mockDiagnostic,
            wakeConnectInitialDelay: .milliseconds(10),
            wakeConnectRetryDelay: .milliseconds(10),
            wakeConnectMaxAttempts: 3
        )

        let config = TVConfiguration(
            name: "Test TV",
            ipAddress: "192.168.1.100",
            macAddress: "AA:BB:CC:DD:EE:FF",
            wakeWithMac: true,
            switchInputOnWake: true
        )
        try controller.saveConfiguration(config)

        mockPowerManager.simulateWakeEvent()

        await waitUntil {
            mockWebOS.connectCallCount == 2 &&
            mockWebOS.sendCommandCalls.contains { if case .setInput = $0.command { return true }; return false }
        }

        #expect(mockWOL.wakeCalls.count == 1)
        #expect(mockWebOS.connectCallCount == 2)
        #expect(mockWebOS.sendCommandCalls.contains { if case .setInput = $0.command { return true }; return false })
    }

    @Test("wake flow ignores duplicate wake events while in progress")
    func wakeFlowIgnoresDuplicateWakeEventsWhileInProgress() async throws {
        let mockPowerManager = MockPowerManager()
        let mockWebOS = MockWebOSClient()
        let mockWOL = MockWOLService()
        let mockKeychain = MockKeychainManager()
        let mockMediaKey = MockMediaKeyManager()
        let mockLaunch = MockLaunchAtLoginManager()
        let mockDiagnostic = MockDiagnosticLogger()

        mockWebOS.asyncDelay = 0.05

        let controller = TVController(
            webOSClient: mockWebOS,
            wolService: mockWOL,
            powerManager: mockPowerManager,
            keychainManager: mockKeychain,
            mediaKeyManager: mockMediaKey,
            launchAtLoginManager: mockLaunch,
            diagnosticLogger: mockDiagnostic,
            wakeConnectInitialDelay: .milliseconds(10),
            wakeConnectRetryDelay: .milliseconds(10),
            wakeConnectMaxAttempts: 3
        )

        let config = TVConfiguration(
            name: "Test TV",
            ipAddress: "192.168.1.100",
            macAddress: "AA:BB:CC:DD:EE:FF",
            wakeWithMac: true
        )
        try controller.saveConfiguration(config)

        mockPowerManager.simulateWakeEvent()
        mockPowerManager.simulateWakeEvent()

        await waitUntil {
            mockWebOS.connectCallCount == 1 &&
            mockDiagnostic.wasLogged(message: "Wake attempt ignored - already in progress")
        }

        #expect(mockWOL.wakeCalls.count == 1)
        #expect(mockWebOS.connectCallCount == 1)
        #expect(mockDiagnostic.wasLogged(message: "Wake attempt ignored - already in progress"))
    }

    @Test("handleMacSleep debounces rapid calls within 10 seconds")
    func handleMacSleepDebounces() async throws {
        let mockPowerManager = MockPowerManager()
        let mockWebOS = MockWebOSClient()
        let mockWOL = MockWOLService()
        let mockKeychain = MockKeychainManager()
        let mockMediaKey = MockMediaKeyManager()
        let mockLaunch = MockLaunchAtLoginManager()
        let mockDiagnostic = MockDiagnosticLogger()

        let controller = TVController(
            webOSClient: mockWebOS,
            wolService: mockWOL,
            powerManager: mockPowerManager,
            keychainManager: mockKeychain,
            mediaKeyManager: mockMediaKey,
            launchAtLoginManager: mockLaunch,
            diagnosticLogger: mockDiagnostic,
            wakeConnectInitialDelay: .milliseconds(10),
            wakeConnectRetryDelay: .milliseconds(10),
            wakeConnectMaxAttempts: 3
        )

        let config = TVConfiguration(
            name: "Test TV",
            ipAddress: "192.168.1.100",
            macAddress: "AA:BB:CC:DD:EE:FF",
            sleepWithMac: true
        )
        try controller.saveConfiguration(config)

        mockPowerManager.simulateSleepEvent()
        try await Task.sleep(for: .milliseconds(50))

        let firstSleepCommandCount = mockWebOS.sendCommandCalls.filter {
            if case .powerOff = $0.command { return true }
            return false
        }.count

        mockPowerManager.simulateSleepEvent()
        try await Task.sleep(for: .milliseconds(50))

        let secondSleepCommandCount = mockWebOS.sendCommandCalls.filter {
            if case .powerOff = $0.command { return true }
            return false
        }.count

        #expect(firstSleepCommandCount == 1)
        #expect(secondSleepCommandCount == firstSleepCommandCount)
    }
}
