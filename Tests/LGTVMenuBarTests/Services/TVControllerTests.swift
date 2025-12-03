import Testing
import Foundation
@testable import LGTVMenuBar

/// Test suite for TVController
@Suite("TVController Tests")
@MainActor
struct TVControllerTests {
    
    // MARK: - Configuration Tests
    
    @Test("Save configuration updates state")
    func saveConfigurationUpdatesState() throws {
        let controller = MockTVController()
        let config = TVConfiguration(
            name: "Test TV",
            ipAddress: "192.168.1.100",
            macAddress: "AA:BB:CC:DD:EE:FF"
        )
        
        try controller.saveConfiguration(config)
        
        #expect(controller.configuration?.name == "Test TV")
        #expect(controller.saveConfigurationCallCount == 1)
    }
    
    @Test("Clear configuration removes state")
    func clearConfigurationRemovesState() throws {
        let controller = MockTVController()
        let config = TVConfiguration(
            name: "Test TV",
            ipAddress: "192.168.1.100",
            macAddress: "AA:BB:CC:DD:EE:FF"
        )
        
        try controller.saveConfiguration(config)
        try controller.clearConfiguration()
        
        #expect(controller.configuration == nil)
        #expect(controller.clearConfigurationCallCount == 1)
    }
    
    // MARK: - Connection Tests
    
    @Test("Connect updates connection state")
    func connectUpdatesConnectionState() async throws {
        let controller = MockTVController()
        let config = TVConfiguration(
            name: "Test TV",
            ipAddress: "192.168.1.100",
            macAddress: "AA:BB:CC:DD:EE:FF"
        )
        
        try controller.saveConfiguration(config)
        try await controller.connect()
        
        #expect(controller.connectionState == .connected)
        #expect(controller.connectCallCount == 1)
    }
    
    @Test("Disconnect updates connection state")
    func disconnectUpdatesConnectionState() {
        let controller = MockTVController()
        controller.connectionState = .connected
        
        controller.disconnect()
        
        #expect(controller.connectionState == .disconnected)
        #expect(controller.disconnectCallCount == 1)
    }
    
    // MARK: - Volume Control Tests
    
    @Test("Volume up increases volume")
    func volumeUpIncreasesVolume() async throws {
        let controller = MockTVController()
        controller.volume = 50
        
        try await controller.volumeUp()
        
        #expect(controller.volume == 55)
        #expect(controller.volumeUpCallCount == 1)
    }
    
    @Test("Volume down decreases volume")
    func volumeDownDecreasesVolume() async throws {
        let controller = MockTVController()
        controller.volume = 50
        
        try await controller.volumeDown()
        
        #expect(controller.volume == 45)
        #expect(controller.volumeDownCallCount == 1)
    }
    
    @Test("Set volume clamps to valid range")
    func setVolumeClamps() async throws {
        let controller = MockTVController()
        
        try await controller.setVolume(150)
        #expect(controller.volume == 100)
        
        try await controller.setVolume(-10)
        #expect(controller.volume == 0)
    }
    
    @Test("Toggle mute changes state")
    func toggleMuteChangesState() async throws {
        let controller = MockTVController()
        controller.isMuted = false
        
        try await controller.toggleMute()
        
        #expect(controller.isMuted == true)
        #expect(controller.toggleMuteCallCount == 1)
    }
    
    // MARK: - Input Control Tests
    
    @Test("Switch input updates current input")
    func switchInputUpdatesCurrentInput() async throws {
        let controller = MockTVController()
        
        try await controller.switchInput(.hdmi2)
        
        #expect(controller.currentInput == .hdmi2)
        #expect(controller.switchInputCallCount == 1)
    }
    
    // MARK: - Error Handling Tests
    
    @Test("Operations throw configured errors")
    func operationsThrowConfiguredErrors() async {
        let controller = MockTVController()
        controller.shouldThrowError = true
        controller.errorToThrow = LGTVError.tvNotFound
        
        await #expect(throws: LGTVError.self) {
            try await controller.connect()
        }
    }
    
    // MARK: - Launch at Login Tests
    
    @Test("Launch at login queries return mock value")
    func launchAtLoginReturnsValue() async throws {
        let controller = MockTVController()
        controller.mockLaunchAtLoginEnabled = true
        
        let enabled = try await controller.isLaunchAtLoginEnabled()
        
        #expect(enabled == true)
        #expect(controller.isLaunchAtLoginEnabledCallCount == 1)
    }
    
    @Test("Set launch at login updates mock value")
    func setLaunchAtLoginUpdatesValue() async throws {
        let controller = MockTVController()
        
        try await controller.setLaunchAtLogin(true)
        
        #expect(controller.mockLaunchAtLoginEnabled == true)
        #expect(controller.setLaunchAtLoginCallCount == 1)
    }
}
