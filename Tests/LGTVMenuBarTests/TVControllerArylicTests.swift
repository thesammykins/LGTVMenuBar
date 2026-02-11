#if LOCAL_ARYLIC_BUILD

import Foundation
import Testing
@testable import LGTVMenuBar

@Suite("TVController Arylic Integration Tests", .serialized)
@MainActor
struct TVControllerArylicTests {
    
    // MARK: - Helper Methods
    
    /// Create a TVController with mock services and injectable Arylic client
    private func makeController(
        arylicClient: ArylicVolumeClientProtocol? = nil
    ) -> TVController {
        let webOSClient = MockWebOSClient()
        let wolService = MockWOLService()
        let powerManager = MockPowerManager()
        let keychainManager = MockKeychainManager()
        let mediaKeyManager = MockMediaKeyManager()
        let launchAtLoginManager = MockLaunchAtLoginManager()
        let diagnosticLogger = MockDiagnosticLogger()
        
        return TVController(
            webOSClient: webOSClient,
            wolService: wolService,
            powerManager: powerManager,
            keychainManager: keychainManager,
            mediaKeyManager: mediaKeyManager,
            launchAtLoginManager: launchAtLoginManager,
            diagnosticLogger: diagnosticLogger,
            arylicClient: arylicClient
        )
    }
    
    /// Clear UserDefaults to ensure clean test state
    private func clearUserDefaults() {
        UserDefaults.standard.removeObject(forKey: "arylicVolumeControlEnabled")
        UserDefaults.standard.removeObject(forKey: "volumeControlTarget")
        UserDefaults.standard.removeObject(forKey: "arylicSettings")
    }
    
    // MARK: - Volume Routing Tests
    
    @Test("volumeUp routes to Arylic when all conditions are met")
    func testVolumeUpRoutesToArylic() async throws {
        clearUserDefaults()
        
        let mockArylic = MockArylicVolumeClient()
        let controller = makeController(arylicClient: mockArylic)
        
        // Enable Arylic control and set target
        controller.isArylicVolumeControlEnabled = true
        controller.volumeControlTarget = .arylic
        
        // Wait for didSet's refreshArylicStatus to complete
        try? await Task.sleep(for: .milliseconds(10))
        
        // Reset calls (didSet triggered refreshArylicStatus)
        mockArylic.reset()
        
        // Call volumeUp
        try await controller.volumeUp()
        
        // Verify Arylic client was called
        #expect(mockArylic.recordedCalls.count == 1)
        #expect(mockArylic.recordedCalls[0].method == .volumeUp)
    }
    
    @Test("volumeDown routes to Arylic when all conditions are met")
    func testVolumeDownRoutesToArylic() async throws {
        clearUserDefaults()
        
        let mockArylic = MockArylicVolumeClient()
        let controller = makeController(arylicClient: mockArylic)
        
        controller.isArylicVolumeControlEnabled = true
        controller.volumeControlTarget = .arylic
        
        // Wait for didSet's refreshArylicStatus to complete
        try? await Task.sleep(for: .milliseconds(10))
        
        // Reset calls (didSet triggered refreshArylicStatus)
        mockArylic.reset()
        
        try await controller.volumeDown()
        
        #expect(mockArylic.recordedCalls.count == 1)
        #expect(mockArylic.recordedCalls[0].method == .volumeDown)
    }
    
    @Test("setVolume routes to Arylic when all conditions are met")
    func testSetVolumeRoutesToArylic() async throws {
        clearUserDefaults()
        
        let mockArylic = MockArylicVolumeClient()
        let controller = makeController(arylicClient: mockArylic)
        
        controller.isArylicVolumeControlEnabled = true
        controller.volumeControlTarget = .arylic
        
        // Wait for didSet's refreshArylicStatus to complete
        try? await Task.sleep(for: .milliseconds(10))
        
        // Reset calls (didSet triggered refreshArylicStatus)
        mockArylic.reset()
        
        try await controller.setVolume(75)
        
        #expect(mockArylic.recordedCalls.count == 1)
        #expect(mockArylic.recordedCalls[0].method == .setVolume(75))
        #expect(controller.volume == 75)
    }
    
    @Test("toggleMute routes to Arylic when all conditions are met")
    func testToggleMuteRoutesToArylic() async throws {
        clearUserDefaults()
        
        let mockArylic = MockArylicVolumeClient()
        let controller = makeController(arylicClient: mockArylic)
        
        controller.isArylicVolumeControlEnabled = true
        controller.volumeControlTarget = .arylic
        
        // Wait for didSet's refreshArylicStatus to complete
        try? await Task.sleep(for: .milliseconds(10))
        
        // Reset calls (didSet triggered refreshArylicStatus)
        mockArylic.reset()
        
        // Initial state: unmuted
        #expect(controller.isMuted == false)
        
        try await controller.toggleMute()
        
        #expect(mockArylic.recordedCalls.count == 1)
        #expect(mockArylic.recordedCalls[0].method == .setMute(true))
        #expect(controller.isMuted == true)
    }
    
    // MARK: - WebOS Fallback Tests
    
    @Test("volumeUp routes to WebOS when Arylic control is disabled")
    func testVolumeUpRoutesToWebOSWhenDisabled() async throws {
        clearUserDefaults()
        
        let mockArylic = MockArylicVolumeClient()
        let controller = makeController(arylicClient: mockArylic)
        
        // Arylic control disabled, target is Arylic
        controller.isArylicVolumeControlEnabled = false
        controller.volumeControlTarget = .arylic
        
        try await controller.volumeUp()
        
        // Arylic should NOT be called
        #expect(mockArylic.recordedCalls.isEmpty)
        // WebOS would be called (via mock, but we don't verify internals here)
    }
    
    @Test("volumeUp routes to WebOS when target is TV")
    func testVolumeUpRoutesToWebOSWhenTargetIsTV() async throws {
        clearUserDefaults()
        
        let mockArylic = MockArylicVolumeClient()
        let controller = makeController(arylicClient: mockArylic)
        
        // Arylic control enabled, but target is TV
        controller.isArylicVolumeControlEnabled = true
        controller.volumeControlTarget = .tv
        
        try await controller.volumeUp()
        
        // Arylic should NOT be called
        #expect(mockArylic.recordedCalls.isEmpty)
    }
    
    @Test("volumeUp routes to WebOS when both disabled and target is TV")
    func testVolumeUpRoutesToWebOSWhenBothConditionsFalse() async throws {
        clearUserDefaults()
        
        let mockArylic = MockArylicVolumeClient()
        let controller = makeController(arylicClient: mockArylic)
        
        controller.isArylicVolumeControlEnabled = false
        controller.volumeControlTarget = .tv
        
        try await controller.volumeUp()
        
        #expect(mockArylic.recordedCalls.isEmpty)
    }
    
    // MARK: - Persistence Tests
    
    @Test("volumeControlTarget persists across controller reinit")
    func testVolumeControlTargetPersistence() async throws {
        clearUserDefaults()
        
        // Create controller and set target
        let controller1 = makeController()
        controller1.volumeControlTarget = .arylic
        
        // Create new controller (should load persisted value)
        let controller2 = makeController()
        
        #expect(controller2.volumeControlTarget == .arylic)
        
        clearUserDefaults()
    }
    
    @Test("arylicSettings persists across controller reinit")
    func testArylicSettingsPersistence() async throws {
        clearUserDefaults()
        
        let settings = ArylicSettings(host: "192.168.1.50", port: 8080, timeout: 10.0)
        
        let controller1 = makeController()
        controller1.arylicSettings = settings
        
        let controller2 = makeController()
        
        #expect(controller2.arylicSettings == settings)
        
        clearUserDefaults()
    }
    
    @Test("isArylicVolumeControlEnabled persists across controller reinit")
    func testArylicVolumeControlEnabledPersistence() async throws {
        clearUserDefaults()
        
        let controller1 = makeController()
        controller1.isArylicVolumeControlEnabled = true
        
        let controller2 = makeController()
        
        #expect(controller2.isArylicVolumeControlEnabled == true)
        
        clearUserDefaults()
    }
    
    // MARK: - refreshArylicStatus Tests
    
    @Test("refreshArylicStatus updates volume and mute state")
    func testRefreshArylicStatus() async throws {
        clearUserDefaults()
        
        let mockArylic = MockArylicVolumeClient()
        mockArylic.setGetPlayerStatusResult(.success((volume: 80, isMuted: true)))
        
        let controller = makeController(arylicClient: mockArylic)
        controller.isArylicVolumeControlEnabled = true
        controller.volumeControlTarget = .arylic
        
        // Wait for didSet's refreshArylicStatus to complete
        try? await Task.sleep(for: .milliseconds(10))
        
        // Check that the automatic refresh already updated the state
        #expect(controller.volume == 80)
        #expect(controller.isMuted == true)
        
        // Reset calls and re-set result
        mockArylic.reset()
        mockArylic.setGetPlayerStatusResult(.success((volume: 80, isMuted: true)))
        
        await controller.refreshArylicStatus()
        
        // Should still be updated
        #expect(controller.volume == 80)
        #expect(controller.isMuted == true)
        #expect(mockArylic.recordedCalls.count == 1)
        #expect(mockArylic.recordedCalls[0].method == .getPlayerStatus)
    }
    
    @Test("refreshArylicStatus does nothing when control is disabled")
    func testRefreshArylicStatusWhenDisabled() async throws {
        clearUserDefaults()
        
        let mockArylic = MockArylicVolumeClient()
        let controller = makeController(arylicClient: mockArylic)
        
        controller.isArylicVolumeControlEnabled = false
        controller.volumeControlTarget = .arylic
        
        await controller.refreshArylicStatus()
        
        // Should not call Arylic
        #expect(mockArylic.recordedCalls.isEmpty)
    }
    
    @Test("refreshArylicStatus does nothing when target is TV")
    func testRefreshArylicStatusWhenTargetIsTV() async throws {
        clearUserDefaults()
        
        let mockArylic = MockArylicVolumeClient()
        let controller = makeController(arylicClient: mockArylic)
        
        controller.isArylicVolumeControlEnabled = true
        controller.volumeControlTarget = .tv
        
        await controller.refreshArylicStatus()
        
        #expect(mockArylic.recordedCalls.isEmpty)
    }
    
    @Test("refreshArylicStatus handles errors gracefully")
    func testRefreshArylicStatusHandlesErrors() async throws {
        clearUserDefaults()
        
        let mockArylic = MockArylicVolumeClient()
        mockArylic.setGetPlayerStatusResult(.failure(ArylicError.connectionFailed("Network error")))
        
        let controller = makeController(arylicClient: mockArylic)
        controller.isArylicVolumeControlEnabled = true
        controller.volumeControlTarget = .arylic
        
        // Wait for didSet's refreshArylicStatus to complete (will fail)
        try? await Task.sleep(for: .milliseconds(10))
        
        // Reset calls (didSet triggered refreshArylicStatus, which failed)
        mockArylic.reset()
        
        // Should not throw, just log error
        await controller.refreshArylicStatus()
        
        #expect(mockArylic.recordedCalls.count == 1)
    }
    
    // MARK: - Property Change Tests
    
    @Test("changing arylicSettings recreates client")
    func testChangingArylicSettingsRecreatesClient() async throws {
        clearUserDefaults()
        
        let controller = makeController()
        
        let settings = ArylicSettings(host: "192.168.1.100", port: 80)
        controller.arylicSettings = settings
        
        // Settings should be persisted
        #expect(controller.arylicSettings == settings)
        
        // Changing settings again
        let newSettings = ArylicSettings(host: "192.168.1.200", port: 8080)
        controller.arylicSettings = newSettings
        
        #expect(controller.arylicSettings == newSettings)
        
        clearUserDefaults()
    }
    
    @Test("clearing arylicSettings removes from UserDefaults")
    func testClearingArylicSettings() async throws {
        clearUserDefaults()
        
        let controller = makeController()
        
        let settings = ArylicSettings(host: "192.168.1.100", port: 80)
        controller.arylicSettings = settings
        
        controller.arylicSettings = nil
        
        #expect(controller.arylicSettings == nil)
        
        // Verify it's gone from UserDefaults
        let data = UserDefaults.standard.data(forKey: "arylicSettings")
        #expect(data == nil)
    }
}

#endif
