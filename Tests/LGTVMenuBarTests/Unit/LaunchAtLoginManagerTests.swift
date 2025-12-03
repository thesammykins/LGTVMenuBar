import Testing
import Foundation
@testable import LGTVMenuBar

/// Test suite for LaunchAtLoginManager and MockLaunchAtLoginManager
/// 
/// Note: Since LaunchAtLoginManager requires ServiceManagement framework access,
/// tests use MockLaunchAtLoginManager to verify behavior.
@Suite("LaunchAtLoginManager Tests")
struct LaunchAtLoginManagerTests {
    
    // MARK: - MockLaunchAtLoginManager Enable Tests
    
    @Test("MockLaunchAtLoginManager enableLaunchAtLogin tracks calls")
    @MainActor
    func mockEnableTracksCalls() async throws {
        let mockManager = MockLaunchAtLoginManager()
        
        try await mockManager.enableLaunchAtLogin()
        try await mockManager.enableLaunchAtLogin()
        
        #expect(mockManager.enableCallCount == 2)
        #expect(mockManager.enableCalls.count == 2)
    }
    
    @Test("MockLaunchAtLoginManager enableLaunchAtLogin sets mockIsEnabled to true")
    @MainActor
    func mockEnableSetsState() async throws {
        let mockManager = MockLaunchAtLoginManager()
        
        #expect(mockManager.mockIsEnabled == false)
        
        try await mockManager.enableLaunchAtLogin()
        
        #expect(mockManager.mockIsEnabled == true)
    }
    
    @Test("MockLaunchAtLoginManager throws on enable when configured")
    @MainActor
    func mockThrowsOnEnable() async {
        let mockManager = MockLaunchAtLoginManager()
        mockManager.shouldThrowOnEnable = true
        
        await #expect(throws: Error.self) {
            try await mockManager.enableLaunchAtLogin()
        }
    }
    
    @Test("MockLaunchAtLoginManager throws custom error on enable when configured")
    @MainActor
    func mockThrowsCustomErrorOnEnable() async {
        let mockManager = MockLaunchAtLoginManager()
        mockManager.shouldThrowOnEnable = true
        mockManager.errorToThrow = LGTVError.launchAtLoginError("Custom enable error")
        
        do {
            try await mockManager.enableLaunchAtLogin()
            Issue.record("Expected error to be thrown")
        } catch {
            #expect(error is LGTVError)
        }
    }
    
    // MARK: - MockLaunchAtLoginManager Disable Tests
    
    @Test("MockLaunchAtLoginManager disableLaunchAtLogin tracks calls")
    @MainActor
    func mockDisableTracksCalls() async throws {
        let mockManager = MockLaunchAtLoginManager()
        
        try await mockManager.disableLaunchAtLogin()
        try await mockManager.disableLaunchAtLogin()
        
        #expect(mockManager.disableCallCount == 2)
        #expect(mockManager.disableCalls.count == 2)
    }
    
    @Test("MockLaunchAtLoginManager disableLaunchAtLogin sets mockIsEnabled to false")
    @MainActor
    func mockDisableClearsState() async throws {
        let mockManager = MockLaunchAtLoginManager()
        mockManager.mockIsEnabled = true
        
        #expect(mockManager.mockIsEnabled == true)
        
        try await mockManager.disableLaunchAtLogin()
        
        #expect(mockManager.mockIsEnabled == false)
    }
    
    @Test("MockLaunchAtLoginManager throws on disable when configured")
    @MainActor
    func mockThrowsOnDisable() async {
        let mockManager = MockLaunchAtLoginManager()
        mockManager.shouldThrowOnDisable = true
        
        await #expect(throws: Error.self) {
            try await mockManager.disableLaunchAtLogin()
        }
    }
    
    @Test("MockLaunchAtLoginManager throws custom error on disable when configured")
    @MainActor
    func mockThrowsCustomErrorOnDisable() async {
        let mockManager = MockLaunchAtLoginManager()
        mockManager.shouldThrowOnDisable = true
        mockManager.errorToThrow = LGTVError.launchAtLoginError("Custom disable error")
        
        do {
            try await mockManager.disableLaunchAtLogin()
            Issue.record("Expected error to be thrown")
        } catch {
            #expect(error is LGTVError)
        }
    }
    
    // MARK: - MockLaunchAtLoginManager IsEnabled Tests
    
    @Test("MockLaunchAtLoginManager isLaunchAtLoginEnabled tracks calls")
    @MainActor
    func mockIsEnabledTracksCalls() async throws {
        let mockManager = MockLaunchAtLoginManager()
        
        _ = try await mockManager.isLaunchAtLoginEnabled()
        _ = try await mockManager.isLaunchAtLoginEnabled()
        
        #expect(mockManager.isEnabledCallCount == 2)
        #expect(mockManager.isEnabledCalls.count == 2)
    }
    
    @Test("MockLaunchAtLoginManager isLaunchAtLoginEnabled returns mock value")
    @MainActor
    func mockIsEnabledReturnsMockValue() async throws {
        let mockManager = MockLaunchAtLoginManager()
        
        mockManager.mockIsEnabled = false
        let result1 = try await mockManager.isLaunchAtLoginEnabled()
        #expect(result1 == false)
        
        mockManager.mockIsEnabled = true
        let result2 = try await mockManager.isLaunchAtLoginEnabled()
        #expect(result2 == true)
    }
    
    @Test("MockLaunchAtLoginManager throws on isEnabled when configured")
    @MainActor
    func mockThrowsOnIsEnabled() async {
        let mockManager = MockLaunchAtLoginManager()
        mockManager.shouldThrowOnIsEnabled = true
        
        await #expect(throws: Error.self) {
            _ = try await mockManager.isLaunchAtLoginEnabled()
        }
    }
    
    @Test("MockLaunchAtLoginManager throws custom error on isEnabled when configured")
    @MainActor
    func mockThrowsCustomErrorOnIsEnabled() async {
        let mockManager = MockLaunchAtLoginManager()
        mockManager.shouldThrowOnIsEnabled = true
        mockManager.errorToThrow = LGTVError.launchAtLoginError("Custom isEnabled error")
        
        do {
            _ = try await mockManager.isLaunchAtLoginEnabled()
            Issue.record("Expected error to be thrown")
        } catch {
            #expect(error is LGTVError)
        }
    }
    
    // MARK: - MockLaunchAtLoginManager Timestamp Tests
    
    @Test("MockLaunchAtLoginManager tracks timestamps for enable calls")
    @MainActor
    func mockTracksEnableTimestamps() async throws {
        let mockManager = MockLaunchAtLoginManager()
        
        let beforeCall = Date()
        try await mockManager.enableLaunchAtLogin()
        let afterCall = Date()
        
        let lastCall = mockManager.lastEnableCall
        #expect(lastCall != nil)
        
        if let timestamp = lastCall {
            #expect(timestamp >= beforeCall)
            #expect(timestamp <= afterCall)
        }
    }
    
    @Test("MockLaunchAtLoginManager tracks timestamps for disable calls")
    @MainActor
    func mockTracksDisableTimestamps() async throws {
        let mockManager = MockLaunchAtLoginManager()
        
        let beforeCall = Date()
        try await mockManager.disableLaunchAtLogin()
        let afterCall = Date()
        
        let lastCall = mockManager.lastDisableCall
        #expect(lastCall != nil)
        
        if let timestamp = lastCall {
            #expect(timestamp >= beforeCall)
            #expect(timestamp <= afterCall)
        }
    }
    
    @Test("MockLaunchAtLoginManager wasEnableCalledRecently returns true for recent calls")
    @MainActor
    func mockWasEnableCalledRecently() async throws {
        let mockManager = MockLaunchAtLoginManager()
        
        #expect(mockManager.wasEnableCalledRecently(within: 5.0) == false)
        
        try await mockManager.enableLaunchAtLogin()
        
        #expect(mockManager.wasEnableCalledRecently(within: 5.0) == true)
    }
    
    @Test("MockLaunchAtLoginManager wasDisableCalledRecently returns true for recent calls")
    @MainActor
    func mockWasDisableCalledRecently() async throws {
        let mockManager = MockLaunchAtLoginManager()
        
        #expect(mockManager.wasDisableCalledRecently(within: 5.0) == false)
        
        try await mockManager.disableLaunchAtLogin()
        
        #expect(mockManager.wasDisableCalledRecently(within: 5.0) == true)
    }
    
    // MARK: - MockLaunchAtLoginManager State Simulation Tests
    
    @Test("MockLaunchAtLoginManager simulateExternalStateChange updates state")
    @MainActor
    func mockSimulateExternalStateChange() async throws {
        let mockManager = MockLaunchAtLoginManager()
        
        #expect(mockManager.mockIsEnabled == false)
        
        mockManager.simulateExternalStateChange(to: true)
        let result1 = try await mockManager.isLaunchAtLoginEnabled()
        #expect(result1 == true)
        
        mockManager.simulateExternalStateChange(to: false)
        let result2 = try await mockManager.isLaunchAtLoginEnabled()
        #expect(result2 == false)
    }
    
    // MARK: - MockLaunchAtLoginManager Reset Tests
    
    @Test("MockLaunchAtLoginManager reset clears all state")
    @MainActor
    func mockResetClearsAllState() async throws {
        let mockManager = MockLaunchAtLoginManager()
        
        // Configure mock
        mockManager.shouldThrowOnEnable = true
        mockManager.shouldThrowOnDisable = true
        mockManager.shouldThrowOnIsEnabled = true
        mockManager.mockIsEnabled = true
        
        // Make some calls (will fail but still record)
        try? await mockManager.enableLaunchAtLogin()
        try? await mockManager.disableLaunchAtLogin()
        _ = try? await mockManager.isLaunchAtLoginEnabled()
        
        // Reset
        mockManager.reset()
        
        // Verify all state is cleared
        #expect(mockManager.enableCallCount == 0)
        #expect(mockManager.disableCallCount == 0)
        #expect(mockManager.isEnabledCallCount == 0)
        #expect(mockManager.shouldThrowOnEnable == false)
        #expect(mockManager.shouldThrowOnDisable == false)
        #expect(mockManager.shouldThrowOnIsEnabled == false)
        #expect(mockManager.mockIsEnabled == false)
    }
    
    // MARK: - MockLaunchAtLoginManager Workflow Tests
    
    @Test("MockLaunchAtLoginManager enable/disable workflow works correctly")
    @MainActor
    func mockEnableDisableWorkflow() async throws {
        let mockManager = MockLaunchAtLoginManager()
        
        // Initial state
        #expect(try await mockManager.isLaunchAtLoginEnabled() == false)
        
        // Enable
        try await mockManager.enableLaunchAtLogin()
        #expect(try await mockManager.isLaunchAtLoginEnabled() == true)
        
        // Disable
        try await mockManager.disableLaunchAtLogin()
        #expect(try await mockManager.isLaunchAtLoginEnabled() == false)
        
        // Verify call counts
        #expect(mockManager.enableCallCount == 1)
        #expect(mockManager.disableCallCount == 1)
        #expect(mockManager.isEnabledCallCount == 3)
    }
    
    @Test("MockLaunchAtLoginManager multiple enables do not change state")
    @MainActor
    func mockMultipleEnables() async throws {
        let mockManager = MockLaunchAtLoginManager()
        
        try await mockManager.enableLaunchAtLogin()
        try await mockManager.enableLaunchAtLogin()
        try await mockManager.enableLaunchAtLogin()
        
        #expect(try await mockManager.isLaunchAtLoginEnabled() == true)
        #expect(mockManager.enableCallCount == 3)
    }
    
    @Test("MockLaunchAtLoginManager multiple disables do not change state")
    @MainActor
    func mockMultipleDisables() async throws {
        let mockManager = MockLaunchAtLoginManager()
        mockManager.mockIsEnabled = true
        
        try await mockManager.disableLaunchAtLogin()
        try await mockManager.disableLaunchAtLogin()
        try await mockManager.disableLaunchAtLogin()
        
        #expect(try await mockManager.isLaunchAtLoginEnabled() == false)
        #expect(mockManager.disableCallCount == 3)
    }
}
