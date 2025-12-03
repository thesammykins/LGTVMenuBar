import Foundation
@testable import LGTVMenuBar

/// Mock implementation of PowerManagerProtocol for testing
@MainActor
final class MockPowerManager: PowerManagerProtocol, Sendable {
    
    // MARK: - Configuration
    
    /// Whether preventSleep should throw an error
    var shouldThrowOnPreventSleep = false
    
    /// Whether allowSleep should throw an error
    var shouldThrowOnAllowSleep = false
    
    /// Error to throw when configured to throw
    var errorToThrow: Error = PowerManagerError.preventSleepFailed(NSError(domain: "MockError", code: 1))
    
    /// Simulated preventing sleep state
    var mockIsPreventingSleep: Bool = false
    
    /// Simulated system sleeping state
    var mockIsSystemSleeping: Bool = false
    
    /// Simulated delay for operations (in seconds)
    var operationDelay: TimeInterval = 0.0
    
    // MARK: - Callbacks
    
    /// Callback when Mac is about to sleep
    var onSleep: (@Sendable () -> Void)?
    
    /// Callback when Mac wakes from sleep
    var onWake: (@Sendable () -> Void)?
    
    /// Callback when display sleeps
    var onScreenSleep: (@Sendable () -> Void)?
    
    /// Callback when display wakes
    var onScreenWake: (@Sendable () -> Void)?
    
    // MARK: - Call History
    
    /// History of preventSleep calls
    private(set) var preventSleepCalls: [Date] = []
    
    /// History of allowSleep calls
    private(set) var allowSleepCalls: [Date] = []
    
    /// History of isSystemSleeping calls
    private(set) var isSystemSleepingCalls: [Date] = []
    
    /// History of startMonitoring calls
    private(set) var startMonitoringCalls: [Date] = []
    
    /// History of stopMonitoring calls
    private(set) var stopMonitoringCalls: [Date] = []
    
    // MARK: - PowerManagerProtocol Implementation
    
    var isPreventingSleep: Bool {
        return mockIsPreventingSleep
    }
    
    func preventSleep() async throws {
        preventSleepCalls.append(Date())
        
        if shouldThrowOnPreventSleep {
            throw errorToThrow
        }
        
        // Simulate async delay if configured
        if operationDelay > 0 {
            try? await Task.sleep(nanoseconds: UInt64(operationDelay * 1_000_000_000))
        }
        
        mockIsPreventingSleep = true
    }
    
    func allowSleep() async throws {
        allowSleepCalls.append(Date())
        
        if shouldThrowOnAllowSleep {
            throw errorToThrow
        }
        
        mockIsPreventingSleep = false
    }
    
    func isSystemSleeping() async -> Bool {
        isSystemSleepingCalls.append(Date())
        return mockIsSystemSleeping
    }
    
    func startMonitoring() {
        startMonitoringCalls.append(Date())
    }
    
    func stopMonitoring() {
        stopMonitoringCalls.append(Date())
    }
    
    // MARK: - Test Helpers
    
    /// Reset all mock state
    func reset() {
        preventSleepCalls.removeAll()
        allowSleepCalls.removeAll()
        isSystemSleepingCalls.removeAll()
        startMonitoringCalls.removeAll()
        stopMonitoringCalls.removeAll()
        
        shouldThrowOnPreventSleep = false
        shouldThrowOnAllowSleep = false
        errorToThrow = PowerManagerError.preventSleepFailed(NSError(domain: "MockError", code: 1))
        mockIsPreventingSleep = false
        mockIsSystemSleeping = false
        operationDelay = 0.0
        
        onSleep = nil
        onWake = nil
        onScreenSleep = nil
        onScreenWake = nil
    }
    
    /// Get the number of times preventSleep was called
    var preventSleepCallCount: Int {
        return preventSleepCalls.count
    }
    
    /// Get the number of times allowSleep was called
    var allowSleepCallCount: Int {
        return allowSleepCalls.count
    }
    
    /// Get the number of times isSystemSleeping was called
    var isSystemSleepingCallCount: Int {
        return isSystemSleepingCalls.count
    }
    
    /// Get the timestamp of the most recent preventSleep call
    var lastPreventSleepCall: Date? {
        return preventSleepCalls.last
    }
    
    /// Get the timestamp of the most recent allowSleep call
    var lastAllowSleepCall: Date? {
        return allowSleepCalls.last
    }
    
    /// Check if preventSleep was called within the specified time interval
    func wasPreventSleepCalledRecently(within interval: TimeInterval) -> Bool {
        guard let lastCall = lastPreventSleepCall else { return false }
        return Date().timeIntervalSince(lastCall) <= interval
    }
    
    /// Check if allowSleep was called within the specified time interval
    func wasAllowSleepCalledRecently(within interval: TimeInterval) -> Bool {
        guard let lastCall = lastAllowSleepCall else { return false }
        return Date().timeIntervalSince(lastCall) <= interval
    }
    
    /// Simulate the preventing sleep state changing externally
    func simulatePreventingSleepStateChange(to preventing: Bool) {
        mockIsPreventingSleep = preventing
    }
    
    /// Simulate the system sleeping state changing
    func simulateSystemSleepingStateChange(to sleeping: Bool) {
        mockIsSystemSleeping = sleeping
    }
    
    /// Get the number of times startMonitoring was called
    var startMonitoringCallCount: Int {
        return startMonitoringCalls.count
    }
    
    /// Get the number of times stopMonitoring was called
    var stopMonitoringCallCount: Int {
        return stopMonitoringCalls.count
    }
    
    /// Simulate a sleep event by calling the onSleep callback
    func simulateSleepEvent() {
        onSleep?()
    }
    
    /// Simulate a wake event by calling the onWake callback
    func simulateWakeEvent() {
        onWake?()
    }
    
    /// Simulate a screen sleep event by calling the onScreenSleep callback
    func simulateScreenSleepEvent() {
        onScreenSleep?()
    }
    
    /// Simulate a screen wake event by calling the onScreenWake callback
    func simulateScreenWakeEvent() {
        onScreenWake?()
    }
}

/// Mock PowerManager errors for testing
enum PowerManagerError: Error, LocalizedError {
    case preventSleepFailed(Error)
    case allowSleepFailed(Error)
    case permissionDenied
    case notSupported
    
    var errorDescription: String? {
        switch self {
        case .preventSleepFailed(let error):
            return "Failed to prevent sleep: \(error.localizedDescription)"
        case .allowSleepFailed(let error):
            return "Failed to allow sleep: \(error.localizedDescription)"
        case .permissionDenied:
            return "Permission denied for power management"
        case .notSupported:
            return "Power management is not supported on this system"
        }
    }
}
