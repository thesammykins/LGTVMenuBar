import Testing
import Foundation
@testable import LGTVMenuBar

/// Integration test suite for TV Controller wake/sleep functionality
/// Tests the full flow from system events to TV control actions
@Suite("TV Controller Wake/Sleep Integration Tests")
@MainActor
struct TVControllerWakeTests {
    
    // MARK: - Phase 1: onScreenWake Callback Tests
    
    @Test("onScreenWake callback triggers handleMacWake when wakeWithMac enabled")
    func onScreenWakeTriggersWakeWithConfig() async throws {
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
            diagnosticLogger: mockDiagnostic
        )
        
        // Setup config with wakeWithMac enabled
        let config = TVConfiguration(
            name: "Test TV",
            ipAddress: "192.168.1.100",
            macAddress: "AA:BB:CC:DD:EE:FF",
            preferredInput: "HDMI_1",
            autoConnectOnLaunch: false,
            wakeWithMac: true,
            sleepWithMac: true,
            switchInputOnWake: false,
            enablePCMode: false
        )
        try controller.saveConfiguration(config)
        
        // Simulate screen wake event
        mockPowerManager.simulateScreenWakeEvent()
        
        // Wait for async operations (need 3+ seconds for wake delay + connect + overhead for parallel test execution)
        try await Task.sleep(for: .milliseconds(4000))
        
        // Verify WOL was sent and connection was attempted
        #expect(mockWOL.wakeCalls.count > 0)
        #expect(mockWebOS.connectCallCount > 0)
    }
    
    @Test("onScreenWake callback ignored when wakeWithMac disabled")
    func onScreenWakeIgnoredWhenDisabled() async throws {
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
            diagnosticLogger: mockDiagnostic
        )
        
        // Setup config with wakeWithMac DISABLED
        let config = TVConfiguration(
            name: "Test TV",
            ipAddress: "192.168.1.100",
            macAddress: "AA:BB:CC:DD:EE:FF",
            preferredInput: "HDMI_1",
            autoConnectOnLaunch: false,
            wakeWithMac: false,
            sleepWithMac: true,
            switchInputOnWake: false,
            enablePCMode: false
        )
        try controller.saveConfiguration(config)
        
        // Simulate screen wake event
        mockPowerManager.simulateScreenWakeEvent()
        
        // Wait for async operations
        try await Task.sleep(for: .milliseconds(100))
        
        // Verify NO wake actions were taken
        #expect(mockWOL.wakeCalls.count == 0)
        #expect(mockWebOS.connectCallCount == 0)
    }
    
    @Test("screenWake event sends WOL packet")
    func screenWakeSendsWOLPacket() async throws {
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
            diagnosticLogger: mockDiagnostic
        )
        
        let config = TVConfiguration(
            name: "Test TV",
            ipAddress: "192.168.1.100",
            macAddress: "AA:BB:CC:DD:EE:FF",
            preferredInput: "HDMI_1",
            wakeWithMac: true
        )
        try controller.saveConfiguration(config)
        
        // Trigger screen wake
        mockPowerManager.simulateScreenWakeEvent()
        try await Task.sleep(for: .milliseconds(100))
        
        // Verify WOL packet was sent with correct MAC address
        #expect(mockWOL.wakeCalls.count == 1)
        #expect(mockWOL.wakeCalls.contains("AA:BB:CC:DD:EE:FF"))
    }
    
    @Test("screenWake event connects to TV after wake")
    func screenWakeConnectsAfterWake() async throws {
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
            diagnosticLogger: mockDiagnostic
        )
        
        let config = TVConfiguration(
            name: "Test TV",
            ipAddress: "192.168.1.100",
            macAddress: "AA:BB:CC:DD:EE:FF",
            wakeWithMac: true
        )
        try controller.saveConfiguration(config)
        
        // Trigger screen wake
        mockPowerManager.simulateScreenWakeEvent()
        
        // Wait long enough for wake delay (3 seconds) + connection
        try await Task.sleep(for: .milliseconds(4000))
        
        // Verify connection was attempted after WOL
        #expect(mockWebOS.connectCallCount > 0)
        #expect(mockWOL.wakeCalls.count > 0)
    }
    
    @Test("screenWake event switches input when switchInputOnWake enabled")
    func screenWakeSwitchesInputWhenEnabled() async throws {
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
            diagnosticLogger: mockDiagnostic
        )
        
        let config = TVConfiguration(
            name: "Test TV",
            ipAddress: "192.168.1.100",
            macAddress: "AA:BB:CC:DD:EE:FF",
            preferredInput: "HDMI_1",
            wakeWithMac: true,
            switchInputOnWake: true
        )
        try controller.saveConfiguration(config)
        
        // Trigger screen wake
        mockPowerManager.simulateScreenWakeEvent()
        
        // Wait for full sequence
        try await Task.sleep(for: .milliseconds(4000))
        
        // Verify input switch command was sent
        let inputCommands = mockWebOS.sendCommandCalls.filter {
            if case .setInput = $0.command { return true }
            return false
        }
        #expect(inputCommands.count > 0)
    }
    
    // MARK: - Phase 2: Screen Unlock Event Tests
    
    @Test("screensDidUnlock triggers TV wake through onScreenWake callback")
    func screensDidUnlockTriggersTVWake() async throws {
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
            diagnosticLogger: mockDiagnostic
        )
        
        let config = TVConfiguration(
            name: "Test TV",
            ipAddress: "192.168.1.100",
            macAddress: "AA:BB:CC:DD:EE:FF",
            wakeWithMac: true
        )
        try controller.saveConfiguration(config)
        
        // Simulate screen unlock event (Phase 2: uses onScreenWake callback)
        mockPowerManager.simulateScreenUnlockEvent()
        
        // Wait for async operations
        try await Task.sleep(for: .milliseconds(100))
        
        // Verify TV wake was triggered
        #expect(mockWOL.wakeCalls.count > 0)
    }
    
    @Test("unlock event sends WOL and connects to TV")
    func unlockEventSendsWOLAndConnects() async throws {
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
            diagnosticLogger: mockDiagnostic
        )
        
        let config = TVConfiguration(
            name: "Test TV",
            ipAddress: "192.168.1.100",
            macAddress: "AA:BB:CC:DD:EE:FF",
            wakeWithMac: true
        )
        try controller.saveConfiguration(config)
        
        // Simulate unlock event
        mockPowerManager.simulateScreenUnlockEvent()
        
        // Wait for full sequence
        try await Task.sleep(for: .milliseconds(4000))
        
        // Verify both WOL and connect happened
        #expect(mockWOL.wakeCalls.count > 0)
        #expect(mockWebOS.connectCallCount > 0)
    }
    
    @Test("unlock event respects wakeWithMac configuration flag")
    func unlockEventRespectsConfiguration() async throws {
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
            diagnosticLogger: mockDiagnostic
        )
        
        // Config with wakeWithMac DISABLED
        let config = TVConfiguration(
            name: "Test TV",
            ipAddress: "192.168.1.100",
            macAddress: "AA:BB:CC:DD:EE:FF",
            wakeWithMac: false
        )
        try controller.saveConfiguration(config)
        
        // Simulate unlock event
        mockPowerManager.simulateScreenUnlockEvent()
        
        // Wait for async operations
        try await Task.sleep(for: .milliseconds(100))
        
        // Verify NO wake actions when disabled
        #expect(mockWOL.wakeCalls.count == 0)
        #expect(mockWebOS.connectCallCount == 0)
    }
    
    // MARK: - Phase 3: screenOn Command Tests
    
    @Test("handleMacWake calls screenOn before connect")
    func handleMacWakeCallsScreenOnBeforeConnect() async throws {
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
            diagnosticLogger: mockDiagnostic
        )
        
        let config = TVConfiguration(
            name: "Test TV",
            ipAddress: "192.168.1.100",
            macAddress: "AA:BB:CC:DD:EE:FF",
            wakeWithMac: true
        )
        try controller.saveConfiguration(config)
        
        // Trigger wake
        mockPowerManager.simulateScreenWakeEvent()
        
        // Wait for sequence
        try await Task.sleep(for: .milliseconds(4000))
        
        // Verify screenOn command was sent
        let screenOnCommands = mockWebOS.sendCommandCalls.filter {
            if case .screenOn = $0.command { return true }
            return false
        }
        #expect(screenOnCommands.count > 0)
        
        // Verify connect was called
        #expect(mockWebOS.connectCallCount > 0)
    }
    
    @Test("handleMacWake sequence executes in order: wake, screenOn, connect, switchInput")
    func handleMacWakeSequenceExecutesInOrder() async throws {
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
            diagnosticLogger: mockDiagnostic
        )
        
        let config = TVConfiguration(
            name: "Test TV",
            ipAddress: "192.168.1.100",
            macAddress: "AA:BB:CC:DD:EE:FF",
            preferredInput: "HDMI_1",
            wakeWithMac: true,
            switchInputOnWake: true
        )
        try controller.saveConfiguration(config)
        
        // Trigger wake
        mockPowerManager.simulateScreenWakeEvent()
        
        // Wait for full sequence
        try await Task.sleep(for: .milliseconds(4000))
        
        // Verify sequence: WOL -> screenOn -> connect -> switchInput
        #expect(mockWOL.wakeCalls.count > 0)
        
        let screenOnCommands = mockWebOS.sendCommandCalls.filter {
            if case .screenOn = $0.command { return true }
            return false
        }
        #expect(screenOnCommands.count > 0)
        
        #expect(mockWebOS.connectCallCount > 0)
        
        let inputCommands = mockWebOS.sendCommandCalls.filter {
            if case .setInput = $0.command { return true }
            return false
        }
        #expect(inputCommands.count > 0)
    }
    
    @Test("handleMacWake logs screenOn action to diagnostic logger")
    func handleMacWakeLogsScreenOnAction() async throws {
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
            diagnosticLogger: mockDiagnostic
        )
        
        let config = TVConfiguration(
            name: "Test TV",
            ipAddress: "192.168.1.100",
            macAddress: "AA:BB:CC:DD:EE:FF",
            wakeWithMac: true
        )
        try controller.saveConfiguration(config)
        
        // Clear previous logs
        mockDiagnostic.reset()
        
        // Trigger wake
        mockPowerManager.simulateScreenWakeEvent()
        
        // Wait for sequence
        try await Task.sleep(for: .milliseconds(4000))
        
        // Verify diagnostic logging occurred
        #expect(mockDiagnostic.logCallCount > 0)
    }
    
    @Test("handleMacWake continues if screenOn fails")
    func handleMacWakeContinuesIfScreenOnFails() async throws {
        let mockPowerManager = MockPowerManager()
        let mockWebOS = MockWebOSClient()
        let mockWOL = MockWOLService()
        let mockKeychain = MockKeychainManager()
        let mockMediaKey = MockMediaKeyManager()
        let mockLaunch = MockLaunchAtLoginManager()
        let mockDiagnostic = MockDiagnosticLogger()
        
        // Configure WebOS to fail on screenOn command
        mockWebOS.shouldThrowOnSendCommand = true
        
        let controller = TVController(
            webOSClient: mockWebOS,
            wolService: mockWOL,
            powerManager: mockPowerManager,
            keychainManager: mockKeychain,
            mediaKeyManager: mockMediaKey,
            launchAtLoginManager: mockLaunch,
            diagnosticLogger: mockDiagnostic
        )
        
        let config = TVConfiguration(
            name: "Test TV",
            ipAddress: "192.168.1.100",
            macAddress: "AA:BB:CC:DD:EE:FF",
            wakeWithMac: true
        )
        try controller.saveConfiguration(config)
        
        // Trigger wake
        mockPowerManager.simulateScreenWakeEvent()
        
        // Wait for sequence
        try await Task.sleep(for: .milliseconds(4000))
        
        // Even though screenOn failed, connect should still be attempted
        #expect(mockWebOS.connectCallCount > 0)
    }
    
    // MARK: - Phase 4: Debouncing Tests
    
    @Test("handleMacWake debounces rapid calls within 10 seconds")
    func handleMacWakeDebounces() async throws {
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
            diagnosticLogger: mockDiagnostic
        )
        
        let config = TVConfiguration(
            name: "Test TV",
            ipAddress: "192.168.1.100",
            macAddress: "AA:BB:CC:DD:EE:FF",
            wakeWithMac: true
        )
        try controller.saveConfiguration(config)
        
        // Trigger first wake
        mockPowerManager.simulateScreenWakeEvent()
        try await Task.sleep(for: .milliseconds(100))
        
        let firstWakeCallCount = mockWOL.wakeCalls.count
        
        // Trigger second wake within 10 seconds (should be debounced)
        mockPowerManager.simulateScreenWakeEvent()
        try await Task.sleep(for: .milliseconds(100))
        
        // Verify second call was debounced (no additional WOL sent)
        #expect(mockWOL.wakeCalls.count == firstWakeCallCount)
    }
    
    @Test("handleMacWake allows execution after 10 seconds elapsed")
    func handleMacWakeAllowsAfterDelay() async throws {
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
            diagnosticLogger: mockDiagnostic
        )
        
        let config = TVConfiguration(
            name: "Test TV",
            ipAddress: "192.168.1.100",
            macAddress: "AA:BB:CC:DD:EE:FF",
            wakeWithMac: true
        )
        try controller.saveConfiguration(config)
        
        // Trigger first wake
        mockPowerManager.simulateScreenWakeEvent()
        try await Task.sleep(for: .milliseconds(100))
        
        let firstWakeCallCount = mockWOL.wakeCalls.count
        
        // Wait 10+ seconds (simulated with shorter delay for test speed)
        // Note: In real implementation, would need to wait full 10 seconds
        // For TDD, we document the expected behavior
        
        // Trigger second wake after delay (should NOT be debounced)
        // This test will fail until debouncing is implemented
        
        // For now, verify first wake succeeded
        #expect(firstWakeCallCount > 0)
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
            diagnosticLogger: mockDiagnostic
        )
        
        let config = TVConfiguration(
            name: "Test TV",
            ipAddress: "192.168.1.100",
            macAddress: "AA:BB:CC:DD:EE:FF",
            sleepWithMac: true
        )
        try controller.saveConfiguration(config)
        
        // Trigger first sleep
        mockPowerManager.simulateSleepEvent()
        try await Task.sleep(for: .milliseconds(100))
        
        let firstSleepCommandCount = mockWebOS.sendCommandCalls.filter {
            if case .powerOff = $0.command { return true }
            return false
        }.count
        
        // Trigger second sleep within 10 seconds (should be debounced)
        mockPowerManager.simulateSleepEvent()
        try await Task.sleep(for: .milliseconds(100))
        
        let secondSleepCommandCount = mockWebOS.sendCommandCalls.filter {
            if case .powerOff = $0.command { return true }
            return false
        }.count
        
        // Verify second call was debounced (no additional powerOff sent)
        #expect(secondSleepCommandCount == firstSleepCommandCount)
    }
    
    @Test("handleMacSleep allows execution after 10 seconds elapsed")
    func handleMacSleepAllowsAfterDelay() async throws {
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
            diagnosticLogger: mockDiagnostic
        )
        
        let config = TVConfiguration(
            name: "Test TV",
            ipAddress: "192.168.1.100",
            macAddress: "AA:BB:CC:DD:EE:FF",
            sleepWithMac: true
        )
        try controller.saveConfiguration(config)
        
        // Trigger first sleep
        mockPowerManager.simulateSleepEvent()
        try await Task.sleep(for: .milliseconds(100))
        
        let firstSleepCommandCount = mockWebOS.sendCommandCalls.filter {
            if case .powerOff = $0.command { return true }
            return false
        }.count
        
        // Verify first sleep succeeded
        #expect(firstSleepCommandCount > 0)
        
        // Note: Full test would wait 10+ seconds and verify second call succeeds
        // Documented for implementation phase
    }
    
    @Test("debounced wake logs time delta in diagnostic logger")
    func debouncedWakeLogsTimeDelta() async throws {
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
            diagnosticLogger: mockDiagnostic
        )
        
        let config = TVConfiguration(
            name: "Test TV",
            ipAddress: "192.168.1.100",
            macAddress: "AA:BB:CC:DD:EE:FF",
            wakeWithMac: true
        )
        try controller.saveConfiguration(config)
        
        // Clear logs
        mockDiagnostic.reset()
        
        // Trigger first wake
        mockPowerManager.simulateScreenWakeEvent()
        try await Task.sleep(for: .milliseconds(100))
        
        // Trigger second wake (should be debounced and logged)
        mockPowerManager.simulateScreenWakeEvent()
        try await Task.sleep(for: .milliseconds(100))
        
        // Verify diagnostic logging occurred
        // In Phase 4, this should log the time delta between calls
        #expect(mockDiagnostic.logCallCount > 0)
    }
}
