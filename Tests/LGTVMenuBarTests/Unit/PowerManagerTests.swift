import Testing
import Foundation
@testable import LGTVMenuBar

/// Thread-safe wrapper for mutable values in sendable closures
final class UncheckedSendableBox<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}

/// Test suite for PowerManager and PowerManagerError
/// 
/// Note: Since PowerManager requires system-level IOKit access,
/// tests use MockPowerManager to verify behavior.
@Suite("PowerManager Tests")
struct PowerManagerTests {
    
    // MARK: - PowerManagerError Tests
    
    @Test("preventSleepFailed error provides localized description")
    func preventSleepFailedErrorDescription() {
        let underlyingError = NSError(domain: "TestDomain", code: 1, userInfo: [NSLocalizedDescriptionKey: "IOKit error"])
        let error = PowerManagerError.preventSleepFailed(underlyingError)
        #expect(error.errorDescription?.contains("Failed to prevent sleep") == true)
    }
    
    @Test("allowSleepFailed error provides localized description")
    func allowSleepFailedErrorDescription() {
        let underlyingError = NSError(domain: "TestDomain", code: 2, userInfo: [NSLocalizedDescriptionKey: "Release failed"])
        let error = PowerManagerError.allowSleepFailed(underlyingError)
        #expect(error.errorDescription?.contains("Failed to allow sleep") == true)
    }
    
    @Test("permissionDenied error provides localized description")
    func permissionDeniedErrorDescription() {
        let error = PowerManagerError.permissionDenied
        #expect(error.errorDescription?.contains("Permission denied") == true)
    }
    
    @Test("notSupported error provides localized description")
    func notSupportedErrorDescription() {
        let error = PowerManagerError.notSupported
        #expect(error.errorDescription?.contains("not supported") == true)
    }
    
    @Test("PowerManagerError conforms to Error protocol")
    func powerManagerErrorConformsToError() {
        let error: Error = PowerManagerError.permissionDenied
        #expect(error is PowerManagerError)
    }
    
    @Test("PowerManagerError conforms to LocalizedError protocol")
    func powerManagerErrorConformsToLocalizedError() {
        let error: LocalizedError = PowerManagerError.permissionDenied
        #expect(error.errorDescription != nil)
    }
    
    // MARK: - MockPowerManager Basic Behavior Tests
    
    @Test("MockPowerManager preventSleep tracks calls")
    @MainActor
    func mockPreventSleepTracksCalls() async throws {
        let mockManager = MockPowerManager()
        
        try await mockManager.preventSleep()
        try await mockManager.preventSleep()
        
        #expect(mockManager.preventSleepCallCount == 2)
        #expect(mockManager.preventSleepCalls.count == 2)
    }
    
    @Test("MockPowerManager preventSleep sets isPreventingSleep to true")
    @MainActor
    func mockPreventSleepSetsState() async throws {
        let mockManager = MockPowerManager()
        
        #expect(mockManager.isPreventingSleep == false)
        
        try await mockManager.preventSleep()
        
        #expect(mockManager.isPreventingSleep == true)
    }
    
    @Test("MockPowerManager allowSleep tracks calls")
    @MainActor
    func mockAllowSleepTracksCalls() async throws {
        let mockManager = MockPowerManager()
        
        try await mockManager.allowSleep()
        try await mockManager.allowSleep()
        
        #expect(mockManager.allowSleepCallCount == 2)
        #expect(mockManager.allowSleepCalls.count == 2)
    }
    
    @Test("MockPowerManager allowSleep sets isPreventingSleep to false")
    @MainActor
    func mockAllowSleepClearsState() async throws {
        let mockManager = MockPowerManager()
        mockManager.mockIsPreventingSleep = true
        
        #expect(mockManager.isPreventingSleep == true)
        
        try await mockManager.allowSleep()
        
        #expect(mockManager.isPreventingSleep == false)
    }
    
    @Test("MockPowerManager isSystemSleeping tracks calls")
    @MainActor
    func mockIsSystemSleepingTracksCalls() async {
        let mockManager = MockPowerManager()
        
        _ = await mockManager.isSystemSleeping()
        _ = await mockManager.isSystemSleeping()
        
        #expect(mockManager.isSystemSleepingCallCount == 2)
        #expect(mockManager.isSystemSleepingCalls.count == 2)
    }
    
    @Test("MockPowerManager isSystemSleeping returns mock value")
    @MainActor
    func mockIsSystemSleepingReturnsMockValue() async {
        let mockManager = MockPowerManager()
        
        mockManager.mockIsSystemSleeping = false
        let result1 = await mockManager.isSystemSleeping()
        #expect(result1 == false)
        
        mockManager.mockIsSystemSleeping = true
        let result2 = await mockManager.isSystemSleeping()
        #expect(result2 == true)
    }
    
    // MARK: - MockPowerManager Error Handling Tests
    
    @Test("MockPowerManager throws on preventSleep when configured")
    @MainActor
    func mockThrowsOnPreventSleep() async {
        let mockManager = MockPowerManager()
        mockManager.shouldThrowOnPreventSleep = true
        
        await #expect(throws: Error.self) {
            try await mockManager.preventSleep()
        }
    }
    
    @Test("MockPowerManager throws on allowSleep when configured")
    @MainActor
    func mockThrowsOnAllowSleep() async {
        let mockManager = MockPowerManager()
        mockManager.shouldThrowOnAllowSleep = true
        
        await #expect(throws: Error.self) {
            try await mockManager.allowSleep()
        }
    }
    
    @Test("MockPowerManager throws custom error when configured")
    @MainActor
    func mockThrowsCustomError() async {
        let mockManager = MockPowerManager()
        mockManager.shouldThrowOnPreventSleep = true
        mockManager.errorToThrow = PowerManagerError.permissionDenied
        
        do {
            try await mockManager.preventSleep()
            Issue.record("Expected error to be thrown")
        } catch {
            #expect(error is PowerManagerError)
        }
    }
    
    // MARK: - MockPowerManager Monitoring Tests
    
    @Test("MockPowerManager startMonitoring tracks calls")
    @MainActor
    func mockStartMonitoringTracksCalls() {
        let mockManager = MockPowerManager()
        
        mockManager.startMonitoring()
        mockManager.startMonitoring()
        
        #expect(mockManager.startMonitoringCallCount == 2)
        #expect(mockManager.startMonitoringCalls.count == 2)
    }
    
    @Test("MockPowerManager stopMonitoring tracks calls")
    @MainActor
    func mockStopMonitoringTracksCalls() {
        let mockManager = MockPowerManager()
        
        mockManager.stopMonitoring()
        mockManager.stopMonitoring()
        
        #expect(mockManager.stopMonitoringCallCount == 2)
        #expect(mockManager.stopMonitoringCalls.count == 2)
    }
    
    // MARK: - MockPowerManager Callback Tests
    
    @Test("MockPowerManager simulateSleepEvent invokes onSleep callback")
    @MainActor
    func mockSimulateSleepEventInvokesCallback() async {
        let mockManager = MockPowerManager()
        let callbackInvoked = UncheckedSendableBox(false)
        
        mockManager.onSleep = {
            callbackInvoked.value = true
        }
        
        mockManager.simulateSleepEvent()
        
        #expect(callbackInvoked.value == true)
    }
    
    @Test("MockPowerManager simulateWakeEvent invokes onWake callback")
    @MainActor
    func mockSimulateWakeEventInvokesCallback() async {
        let mockManager = MockPowerManager()
        let callbackInvoked = UncheckedSendableBox(false)
        
        mockManager.onWake = {
            callbackInvoked.value = true
        }
        
        mockManager.simulateWakeEvent()
        
        #expect(callbackInvoked.value == true)
    }
    
    @Test("MockPowerManager simulateScreenSleepEvent invokes onScreenSleep callback")
    @MainActor
    func mockSimulateScreenSleepEventInvokesCallback() async {
        let mockManager = MockPowerManager()
        let callbackInvoked = UncheckedSendableBox(false)
        
        mockManager.onScreenSleep = {
            callbackInvoked.value = true
        }
        
        mockManager.simulateScreenSleepEvent()
        
        #expect(callbackInvoked.value == true)
    }
    
    @Test("MockPowerManager simulateScreenWakeEvent invokes onScreenWake callback")
    @MainActor
    func mockSimulateScreenWakeEventInvokesCallback() async {
        let mockManager = MockPowerManager()
        let callbackInvoked = UncheckedSendableBox(false)
        
        mockManager.onScreenWake = {
            callbackInvoked.value = true
        }
        
        mockManager.simulateScreenWakeEvent()
        
        #expect(callbackInvoked.value == true)
    }
    
    @Test("MockPowerManager callback simulation is safe when callback is nil")
    @MainActor
    func mockCallbackSimulationIsSafeWithNilCallback() {
        let mockManager = MockPowerManager()
        
        // Should not crash when callbacks are nil
        mockManager.simulateSleepEvent()
        mockManager.simulateWakeEvent()
        mockManager.simulateScreenSleepEvent()
        mockManager.simulateScreenWakeEvent()
        
        // If we reach here without crashing, the test passes
        #expect(Bool(true))
    }
    
    // MARK: - MockPowerManager State Simulation Tests
    
    @Test("MockPowerManager simulatePreventingSleepStateChange updates state")
    @MainActor
    func mockSimulatePreventingSleepStateChange() {
        let mockManager = MockPowerManager()
        
        #expect(mockManager.isPreventingSleep == false)
        
        mockManager.simulatePreventingSleepStateChange(to: true)
        #expect(mockManager.isPreventingSleep == true)
        
        mockManager.simulatePreventingSleepStateChange(to: false)
        #expect(mockManager.isPreventingSleep == false)
    }
    
    @Test("MockPowerManager simulateSystemSleepingStateChange updates state")
    @MainActor
    func mockSimulateSystemSleepingStateChange() async {
        let mockManager = MockPowerManager()
        
        mockManager.simulateSystemSleepingStateChange(to: false)
        let result1 = await mockManager.isSystemSleeping()
        #expect(result1 == false)
        
        mockManager.simulateSystemSleepingStateChange(to: true)
        let result2 = await mockManager.isSystemSleeping()
        #expect(result2 == true)
    }
    
    // MARK: - MockPowerManager Timestamp Tests
    
    @Test("MockPowerManager tracks timestamps for preventSleep calls")
    @MainActor
    func mockTracksPreventSleepTimestamps() async throws {
        let mockManager = MockPowerManager()
        
        let beforeCall = Date()
        try await mockManager.preventSleep()
        let afterCall = Date()
        
        let lastCall = mockManager.lastPreventSleepCall
        #expect(lastCall != nil)
        
        if let timestamp = lastCall {
            #expect(timestamp >= beforeCall)
            #expect(timestamp <= afterCall)
        }
    }
    
    @Test("MockPowerManager tracks timestamps for allowSleep calls")
    @MainActor
    func mockTracksAllowSleepTimestamps() async throws {
        let mockManager = MockPowerManager()
        
        let beforeCall = Date()
        try await mockManager.allowSleep()
        let afterCall = Date()
        
        let lastCall = mockManager.lastAllowSleepCall
        #expect(lastCall != nil)
        
        if let timestamp = lastCall {
            #expect(timestamp >= beforeCall)
            #expect(timestamp <= afterCall)
        }
    }
    
    @Test("MockPowerManager wasPreventSleepCalledRecently returns true for recent calls")
    @MainActor
    func mockWasPreventSleepCalledRecently() async throws {
        let mockManager = MockPowerManager()
        
        #expect(mockManager.wasPreventSleepCalledRecently(within: 5.0) == false)
        
        try await mockManager.preventSleep()
        
        #expect(mockManager.wasPreventSleepCalledRecently(within: 5.0) == true)
    }
    
    @Test("MockPowerManager wasAllowSleepCalledRecently returns true for recent calls")
    @MainActor
    func mockWasAllowSleepCalledRecently() async throws {
        let mockManager = MockPowerManager()
        
        #expect(mockManager.wasAllowSleepCalledRecently(within: 5.0) == false)
        
        try await mockManager.allowSleep()
        
        #expect(mockManager.wasAllowSleepCalledRecently(within: 5.0) == true)
    }
    
    // MARK: - MockPowerManager Delay Tests
    
    @Test("MockPowerManager respects configured delay for preventSleep")
    @MainActor
    func mockRespectsPreventSleepDelay() async throws {
        let mockManager = MockPowerManager()
        mockManager.operationDelay = 0.1
        
        let startTime = Date()
        try await mockManager.preventSleep()
        let endTime = Date()
        
        let elapsed = endTime.timeIntervalSince(startTime)
        #expect(elapsed >= 0.09) // Allow small margin for timing
    }
    
    // MARK: - MockPowerManager Reset Tests
    
    @Test("MockPowerManager reset clears all state")
    @MainActor
    func mockResetClearsAllState() async throws {
        let mockManager = MockPowerManager()
        
        // Configure mock
        mockManager.shouldThrowOnPreventSleep = true
        mockManager.shouldThrowOnAllowSleep = true
        mockManager.operationDelay = 1.0
        mockManager.mockIsPreventingSleep = true
        mockManager.mockIsSystemSleeping = true
        mockManager.onSleep = {}
        mockManager.onWake = {}
        mockManager.onScreenSleep = {}
        mockManager.onScreenWake = {}
        
        // Make some calls (will fail but still record)
        try? await mockManager.preventSleep()
        try? await mockManager.allowSleep()
        _ = await mockManager.isSystemSleeping()
        mockManager.startMonitoring()
        mockManager.stopMonitoring()
        
        // Reset
        mockManager.reset()
        
        // Verify all state is cleared
        #expect(mockManager.preventSleepCallCount == 0)
        #expect(mockManager.allowSleepCallCount == 0)
        #expect(mockManager.isSystemSleepingCallCount == 0)
        #expect(mockManager.startMonitoringCallCount == 0)
        #expect(mockManager.stopMonitoringCallCount == 0)
        #expect(mockManager.shouldThrowOnPreventSleep == false)
        #expect(mockManager.shouldThrowOnAllowSleep == false)
        #expect(mockManager.operationDelay == 0.0)
        #expect(mockManager.mockIsPreventingSleep == false)
        #expect(mockManager.mockIsSystemSleeping == false)
        #expect(mockManager.onSleep == nil)
        #expect(mockManager.onWake == nil)
        #expect(mockManager.onScreenSleep == nil)
        #expect(mockManager.onScreenWake == nil)
    }
}
