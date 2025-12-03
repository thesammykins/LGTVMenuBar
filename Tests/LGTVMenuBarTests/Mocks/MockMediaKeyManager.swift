import Foundation
@testable import LGTVMenuBar

/// Mock implementation of MediaKeyManagerProtocol for testing
@MainActor
final class MockMediaKeyManager: MediaKeyManagerProtocol, @unchecked Sendable {
    
    // MARK: - Configuration
    
    /// Whether startMediaKeyCapture should throw an error
    var shouldThrowOnStartCapture = false
    
    /// Whether stopMediaKeyCapture should throw an error
    var shouldThrowOnStopCapture = false
    
    /// Error to throw when configured to throw
    var errorToThrow: Error = LGTVError.mediaKeyError("Permission denied")
    
    /// Simulated capturing state
    var mockIsCapturingMediaKeys: Bool = false
    
    /// Whether media keys should be captured (vs passed through)
    var shouldCaptureMediaKeys: Bool = true
    
    /// Simulated accessibility permission state
    var mockHasAccessibilityPermission: Bool = true
    
    /// Simulated delay for capture operations (in seconds)
    var captureDelay: TimeInterval = 0.0
    
    // MARK: - Call History
    
    /// History of startMediaKeyCapture calls
    private(set) var startCaptureCalls: [Date] = []
    
    /// History of stopMediaKeyCapture calls
    private(set) var stopCaptureCalls: [Date] = []
    
    /// History of callback invocations
    private(set) var callbackInvocations: [(MediaKey, Date)] = []
    
    // MARK: - Stored Callback
    
    private var storedCallback: (@Sendable (MediaKey) -> Void)?
    
    // MARK: - MediaKeyManagerProtocol Implementation
    
    var isCapturingMediaKeys: Bool {
        return mockIsCapturingMediaKeys
    }
    
    var hasAccessibilityPermission: Bool {
        return mockHasAccessibilityPermission
    }
    
    func requestAccessibilityPermission() -> Bool {
        // In mock, just return the mock state
        return mockHasAccessibilityPermission
    }
    
    func startMediaKeyCapture(callback: @escaping @Sendable (MediaKey) -> Void) async throws {
        startCaptureCalls.append(Date())
        
        if shouldThrowOnStartCapture {
            throw errorToThrow
        }
        
        // Simulate async delay if configured
        if captureDelay > 0 {
            try await Task.sleep(nanoseconds: UInt64(captureDelay * 1_000_000_000))
        }
        
        storedCallback = callback
        mockIsCapturingMediaKeys = true
    }
    
    func stopMediaKeyCapture() async throws {
        stopCaptureCalls.append(Date())
        
        if shouldThrowOnStopCapture {
            throw errorToThrow
        }
        
        storedCallback = nil
        mockIsCapturingMediaKeys = false
    }
    
    // MARK: - Test Helpers
    
    /// Reset all mock state
    func reset() {
        startCaptureCalls.removeAll()
        stopCaptureCalls.removeAll()
        callbackInvocations.removeAll()
        
        shouldThrowOnStartCapture = false
        shouldThrowOnStopCapture = false
        errorToThrow = LGTVError.mediaKeyError("Permission denied")
        mockIsCapturingMediaKeys = false
        shouldCaptureMediaKeys = true
        mockHasAccessibilityPermission = true
        captureDelay = 0.0
        storedCallback = nil
    }
    
    /// Get number of times startMediaKeyCapture was called
    var startCaptureCallCount: Int {
        return startCaptureCalls.count
    }
    
    /// Get number of times stopMediaKeyCapture was called
    var stopCaptureCallCount: Int {
        return stopCaptureCalls.count
    }
    
    /// Get timestamp of most recent startMediaKeyCapture call
    var lastStartCaptureCall: Date? {
        return startCaptureCalls.last
    }
    
    /// Get timestamp of most recent stopMediaKeyCapture call
    var lastStopCaptureCall: Date? {
        return stopCaptureCalls.last
    }
    
    /// Simulate a media key press
    func simulateMediaKey(_ key: MediaKey) {
        callbackInvocations.append((key, Date()))
        storedCallback?(key)
    }
    
    /// Get number of times a specific media key was simulated
    func callCountFor(mediaKey: MediaKey) -> Int {
        return callbackInvocations.filter { $0.0 == mediaKey }.count
    }
    
    /// Check if startMediaKeyCapture was called within the specified time interval
    func wasStartCaptureCalledRecently(within interval: TimeInterval) -> Bool {
        guard let lastCall = lastStartCaptureCall else { return false }
        return Date().timeIntervalSince(lastCall) <= interval
    }
    
    /// Check if stopMediaKeyCapture was called within the specified time interval
    func wasStopCaptureCalledRecently(within interval: TimeInterval) -> Bool {
        guard let lastCall = lastStopCaptureCall else { return false }
        return Date().timeIntervalSince(lastCall) <= interval
    }
}
