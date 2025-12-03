import Foundation
@testable import LGTVMenuBar

/// Mock implementation of WOLServiceProtocol for testing
final class MockWOLService: WOLServiceProtocol, @unchecked Sendable {
    
    // MARK: - Configuration
    
    /// Whether wake operations should throw an error
    var shouldThrowOnWake = false
    
    /// Error to throw when configured to throw
    var errorToThrow: Error = LGTVError.wolError(NSError(domain: "MockWOL", code: -1))
    
    /// Simulated delay for wake operations (in seconds)
    var wakeDelay: TimeInterval = 0.0
    
    /// Whether wake operation should succeed
    var shouldSucceedWake = true
    
    // MARK: - Call History
    
    /// History of wake calls
    private(set) var wakeCalls: [String] = []
    
    /// History of wake calls with timestamps
    private(set) var wakeCallTimestamps: [(macAddress: String, timestamp: Date)] = []
    
    // MARK: - WOLServiceProtocol Implementation
    
    func sendWakeRequest(to configuration: TVConfiguration) async throws {
        try await sendWakeOnLAN(macAddress: configuration.macAddress)
    }
    
    func sendWakeOnLAN(macAddress: String) async throws {
        wakeCalls.append(macAddress)
        wakeCallTimestamps.append((macAddress: macAddress, timestamp: Date()))
        
        if shouldThrowOnWake {
            throw errorToThrow
        }
        
        if !shouldSucceedWake {
            throw LGTVError.wolError(NSError(domain: "MockWOL", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid MAC: \(macAddress)"]))
        }
        
        // Simulate network delay if configured
        if wakeDelay > 0 {
            try await Task.sleep(for: .seconds(wakeDelay))
        }
    }
    
    // MARK: - Test Helpers
    
    /// Reset all mock state
    func reset() {
        wakeCalls.removeAll()
        wakeCallTimestamps.removeAll()
        
        shouldThrowOnWake = false
        shouldSucceedWake = true
        errorToThrow = LGTVError.wolError(NSError(domain: "MockWOL", code: -1))
        wakeDelay = 0.0
    }
    
    /// Get the number of times wake was called for a specific MAC address
    func wakeCallCount(for macAddress: String) -> Int {
        return wakeCalls.filter { $0 == macAddress }.count
    }
    
    /// Get the most recent wake call for a specific MAC address
    func lastWakeCall(for macAddress: String) -> Date? {
        return wakeCallTimestamps
            .filter { $0.macAddress == macAddress }
            .last?
            .timestamp
    }
    
    /// Check if wake was called within the specified time interval
    func wasWakeCalledRecently(for macAddress: String, within interval: TimeInterval) -> Bool {
        guard let lastCall = lastWakeCall(for: macAddress) else { return false }
        return Date().timeIntervalSince(lastCall) <= interval
    }
    
    /// Get all wake calls sorted by timestamp
    func allWakeCallsSorted() -> [(macAddress: String, timestamp: Date)] {
        return wakeCallTimestamps.sorted { $0.timestamp < $1.timestamp }
    }
}