import Foundation
@testable import LGTVMenuBar

/// Mock implementation of LaunchAtLoginManagerProtocol for testing
@MainActor
final class MockLaunchAtLoginManager: LaunchAtLoginManagerProtocol, @unchecked Sendable {
    
    // MARK: - Configuration
    
    /// Whether enable operations should throw an error
    var shouldThrowOnEnable = false
    
    /// Whether disable operations should throw an error
    var shouldThrowOnDisable = false
    
    /// Whether isEnabled check should throw an error
    var shouldThrowOnIsEnabled = false
    
    /// Error to throw when configured to throw
    var errorToThrow: Error = LGTVError.launchAtLoginError("Mock error")
    
    /// Simulated enabled state
    var mockIsEnabled: Bool = false
    
    // MARK: - Call History
    
    /// History of enable calls
    private(set) var enableCalls: [Date] = []
    
    /// History of disable calls
    private(set) var disableCalls: [Date] = []
    
    /// History of isEnabled checks
    private(set) var isEnabledCalls: [Date] = []
    
    // MARK: - LaunchAtLoginManagerProtocol Implementation
    
    func enableLaunchAtLogin() async throws {
        enableCalls.append(Date())
        
        if shouldThrowOnEnable {
            throw errorToThrow
        }
        
        mockIsEnabled = true
    }
    
    func disableLaunchAtLogin() async throws {
        disableCalls.append(Date())
        
        if shouldThrowOnDisable {
            throw errorToThrow
        }
        
        mockIsEnabled = false
    }
    
    func isLaunchAtLoginEnabled() async throws -> Bool {
        isEnabledCalls.append(Date())
        
        if shouldThrowOnIsEnabled {
            throw errorToThrow
        }
        
        return mockIsEnabled
    }
    
    // MARK: - Test Helpers
    
    /// Reset all mock state
    func reset() {
        enableCalls.removeAll()
        disableCalls.removeAll()
        isEnabledCalls.removeAll()
        
        shouldThrowOnEnable = false
        shouldThrowOnDisable = false
        shouldThrowOnIsEnabled = false
        errorToThrow = LGTVError.launchAtLoginError("Mock error")
        mockIsEnabled = false
    }
    
    /// Get the number of times enable was called
    var enableCallCount: Int {
        return enableCalls.count
    }
    
    /// Get the number of times disable was called
    var disableCallCount: Int {
        return disableCalls.count
    }
    
    /// Get the number of times isEnabled was checked
    var isEnabledCallCount: Int {
        return isEnabledCalls.count
    }
    
    /// Get the timestamp of the most recent enable call
    var lastEnableCall: Date? {
        return enableCalls.last
    }
    
    /// Get the timestamp of the most recent disable call
    var lastDisableCall: Date? {
        return disableCalls.last
    }
    
    /// Check if enable was called within the specified time interval
    func wasEnableCalledRecently(within interval: TimeInterval) -> Bool {
        guard let lastCall = lastEnableCall else { return false }
        return Date().timeIntervalSince(lastCall) <= interval
    }
    
    /// Check if disable was called within the specified time interval
    func wasDisableCalledRecently(within interval: TimeInterval) -> Bool {
        guard let lastCall = lastDisableCall else { return false }
        return Date().timeIntervalSince(lastCall) <= interval
    }
    
    /// Simulate the enabled state changing externally
    func simulateExternalStateChange(to enabled: Bool) {
        mockIsEnabled = enabled
    }
}