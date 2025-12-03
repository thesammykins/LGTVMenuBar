import Testing
import Foundation
@testable import LGTVMenuBar

/// Thread-safe wrapper for mutable values in sendable closures
final class MediaKeyTestBox<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}

/// Test suite for MediaKeyManager and MockMediaKeyManager
/// 
/// Note: Since MediaKeyManager requires system-level accessibility permissions
/// and Carbon event tap access, tests use MockMediaKeyManager to verify behavior.
@Suite("MediaKeyManager Tests")
struct MediaKeyManagerTests {
    
    // MARK: - MediaKey Enum Tests
    
    @Test("MediaKey has all expected cases")
    func mediaKeyHasAllExpectedCases() {
        let allCases = MediaKey.allCases
        #expect(allCases.count == 3)
        #expect(allCases.contains(.volumeUp))
        #expect(allCases.contains(.volumeDown))
        #expect(allCases.contains(.mute))
    }
    
    @Test("MediaKey rawValue returns expected strings")
    func mediaKeyRawValues() {
        #expect(MediaKey.volumeUp.rawValue == "volumeUp")
        #expect(MediaKey.volumeDown.rawValue == "volumeDown")
        #expect(MediaKey.mute.rawValue == "mute")
    }
    
    @Test("MediaKey can be initialized from rawValue")
    func mediaKeyInitFromRawValue() {
        #expect(MediaKey(rawValue: "volumeUp") == .volumeUp)
        #expect(MediaKey(rawValue: "volumeDown") == .volumeDown)
        #expect(MediaKey(rawValue: "mute") == .mute)
        #expect(MediaKey(rawValue: "invalid") == nil)
    }
    
    @Test("MediaKey conforms to Sendable")
    func mediaKeyIsSendable() {
        let key: Sendable = MediaKey.volumeUp
        #expect(key is MediaKey)
    }
    
    // MARK: - MockMediaKeyManager Basic Behavior Tests
    
    @Test("MockMediaKeyManager startMediaKeyCapture tracks calls")
    @MainActor
    func mockStartCaptureTracksCalls() async throws {
        let mockManager = MockMediaKeyManager()
        
        try await mockManager.startMediaKeyCapture { _ in }
        
        #expect(mockManager.startCaptureCallCount == 1)
        #expect(mockManager.startCaptureCalls.count == 1)
    }
    
    @Test("MockMediaKeyManager startMediaKeyCapture sets isCapturingMediaKeys to true")
    @MainActor
    func mockStartCaptureSetsState() async throws {
        let mockManager = MockMediaKeyManager()
        
        #expect(mockManager.isCapturingMediaKeys == false)
        
        try await mockManager.startMediaKeyCapture { _ in }
        
        #expect(mockManager.isCapturingMediaKeys == true)
    }
    
    @Test("MockMediaKeyManager stopMediaKeyCapture tracks calls")
    @MainActor
    func mockStopCaptureTracksCalls() async throws {
        let mockManager = MockMediaKeyManager()
        
        try await mockManager.stopMediaKeyCapture()
        try await mockManager.stopMediaKeyCapture()
        
        #expect(mockManager.stopCaptureCallCount == 2)
        #expect(mockManager.stopCaptureCalls.count == 2)
    }
    
    @Test("MockMediaKeyManager stopMediaKeyCapture sets isCapturingMediaKeys to false")
    @MainActor
    func mockStopCaptureClearsState() async throws {
        let mockManager = MockMediaKeyManager()
        mockManager.mockIsCapturingMediaKeys = true
        
        #expect(mockManager.isCapturingMediaKeys == true)
        
        try await mockManager.stopMediaKeyCapture()
        
        #expect(mockManager.isCapturingMediaKeys == false)
    }
    
    // MARK: - MockMediaKeyManager Error Handling Tests
    
    @Test("MockMediaKeyManager throws on startMediaKeyCapture when configured")
    @MainActor
    func mockThrowsOnStartCapture() async {
        let mockManager = MockMediaKeyManager()
        mockManager.shouldThrowOnStartCapture = true
        
        await #expect(throws: Error.self) {
            try await mockManager.startMediaKeyCapture { _ in }
        }
    }
    
    @Test("MockMediaKeyManager throws on stopMediaKeyCapture when configured")
    @MainActor
    func mockThrowsOnStopCapture() async {
        let mockManager = MockMediaKeyManager()
        mockManager.shouldThrowOnStopCapture = true
        
        await #expect(throws: Error.self) {
            try await mockManager.stopMediaKeyCapture()
        }
    }
    
    @Test("MockMediaKeyManager throws custom error when configured")
    @MainActor
    func mockThrowsCustomError() async {
        let mockManager = MockMediaKeyManager()
        mockManager.shouldThrowOnStartCapture = true
        mockManager.errorToThrow = LGTVError.mediaKeyError("Custom error")
        
        do {
            try await mockManager.startMediaKeyCapture { _ in }
            Issue.record("Expected error to be thrown")
        } catch {
            #expect(error is LGTVError)
        }
    }
    
    // MARK: - MockMediaKeyManager Callback Tests
    
    @Test("MockMediaKeyManager simulateMediaKey invokes stored callback")
    @MainActor
    func mockSimulateMediaKeyInvokesCallback() async throws {
        let mockManager = MockMediaKeyManager()
        let receivedKey = MediaKeyTestBox<MediaKey?>(nil)
        
        try await mockManager.startMediaKeyCapture { key in
            receivedKey.value = key
        }
        
        mockManager.simulateMediaKey(.volumeUp)
        
        #expect(receivedKey.value == .volumeUp)
    }
    
    @Test("MockMediaKeyManager simulateMediaKey tracks callback invocations")
    @MainActor
    func mockSimulateMediaKeyTracksInvocations() async throws {
        let mockManager = MockMediaKeyManager()
        
        try await mockManager.startMediaKeyCapture { _ in }
        
        mockManager.simulateMediaKey(.volumeUp)
        mockManager.simulateMediaKey(.volumeDown)
        mockManager.simulateMediaKey(.mute)
        
        #expect(mockManager.callbackInvocations.count == 3)
        #expect(mockManager.callbackInvocations[0].0 == .volumeUp)
        #expect(mockManager.callbackInvocations[1].0 == .volumeDown)
        #expect(mockManager.callbackInvocations[2].0 == .mute)
    }
    
    @Test("MockMediaKeyManager simulateMediaKey is safe when no callback registered")
    @MainActor
    func mockSimulateMediaKeyIsSafeWithNoCallback() {
        let mockManager = MockMediaKeyManager()
        
        // Should not crash when no callback is registered
        mockManager.simulateMediaKey(.volumeUp)
        
        // Invocation should still be tracked
        #expect(mockManager.callbackInvocations.count == 1)
    }
    
    @Test("MockMediaKeyManager callCountFor returns correct count for specific key")
    @MainActor
    func mockCallCountForReturnsCorrectCount() async throws {
        let mockManager = MockMediaKeyManager()
        
        try await mockManager.startMediaKeyCapture { _ in }
        
        mockManager.simulateMediaKey(.volumeUp)
        mockManager.simulateMediaKey(.volumeUp)
        mockManager.simulateMediaKey(.volumeDown)
        mockManager.simulateMediaKey(.mute)
        
        #expect(mockManager.callCountFor(mediaKey: .volumeUp) == 2)
        #expect(mockManager.callCountFor(mediaKey: .volumeDown) == 1)
        #expect(mockManager.callCountFor(mediaKey: .mute) == 1)
    }
    
    // MARK: - MockMediaKeyManager Timestamp Tests
    
    @Test("MockMediaKeyManager tracks timestamps for startMediaKeyCapture calls")
    @MainActor
    func mockTracksStartCaptureTimestamps() async throws {
        let mockManager = MockMediaKeyManager()
        
        let beforeCall = Date()
        try await mockManager.startMediaKeyCapture { _ in }
        let afterCall = Date()
        
        let lastCall = mockManager.lastStartCaptureCall
        #expect(lastCall != nil)
        
        if let timestamp = lastCall {
            #expect(timestamp >= beforeCall)
            #expect(timestamp <= afterCall)
        }
    }
    
    @Test("MockMediaKeyManager tracks timestamps for stopMediaKeyCapture calls")
    @MainActor
    func mockTracksStopCaptureTimestamps() async throws {
        let mockManager = MockMediaKeyManager()
        
        let beforeCall = Date()
        try await mockManager.stopMediaKeyCapture()
        let afterCall = Date()
        
        let lastCall = mockManager.lastStopCaptureCall
        #expect(lastCall != nil)
        
        if let timestamp = lastCall {
            #expect(timestamp >= beforeCall)
            #expect(timestamp <= afterCall)
        }
    }
    
    @Test("MockMediaKeyManager wasStartCaptureCalledRecently returns true for recent calls")
    @MainActor
    func mockWasStartCaptureCalledRecently() async throws {
        let mockManager = MockMediaKeyManager()
        
        #expect(mockManager.wasStartCaptureCalledRecently(within: 5.0) == false)
        
        try await mockManager.startMediaKeyCapture { _ in }
        
        #expect(mockManager.wasStartCaptureCalledRecently(within: 5.0) == true)
    }
    
    @Test("MockMediaKeyManager wasStopCaptureCalledRecently returns true for recent calls")
    @MainActor
    func mockWasStopCaptureCalledRecently() async throws {
        let mockManager = MockMediaKeyManager()
        
        #expect(mockManager.wasStopCaptureCalledRecently(within: 5.0) == false)
        
        try await mockManager.stopMediaKeyCapture()
        
        #expect(mockManager.wasStopCaptureCalledRecently(within: 5.0) == true)
    }
    
    // MARK: - MockMediaKeyManager Delay Tests
    
    @Test("MockMediaKeyManager respects configured delay for startMediaKeyCapture")
    @MainActor
    func mockRespectsStartCaptureDelay() async throws {
        let mockManager = MockMediaKeyManager()
        mockManager.captureDelay = 0.1
        
        let startTime = Date()
        try await mockManager.startMediaKeyCapture { _ in }
        let endTime = Date()
        
        let elapsed = endTime.timeIntervalSince(startTime)
        #expect(elapsed >= 0.09) // Allow small margin for timing
    }
    
    // MARK: - MockMediaKeyManager Reset Tests
    
    @Test("MockMediaKeyManager reset clears all state")
    @MainActor
    func mockResetClearsAllState() async throws {
        let mockManager = MockMediaKeyManager()
        
        // Configure mock
        mockManager.shouldThrowOnStartCapture = true
        mockManager.shouldThrowOnStopCapture = true
        mockManager.captureDelay = 1.0
        mockManager.mockIsCapturingMediaKeys = true
        mockManager.shouldCaptureMediaKeys = false
        
        // Make some calls (will fail but still record)
        try? await mockManager.startMediaKeyCapture { _ in }
        try? await mockManager.stopMediaKeyCapture()
        mockManager.simulateMediaKey(.volumeUp)
        
        // Reset
        mockManager.reset()
        
        // Verify all state is cleared
        #expect(mockManager.startCaptureCallCount == 0)
        #expect(mockManager.stopCaptureCallCount == 0)
        #expect(mockManager.callbackInvocations.isEmpty)
        #expect(mockManager.shouldThrowOnStartCapture == false)
        #expect(mockManager.shouldThrowOnStopCapture == false)
        #expect(mockManager.captureDelay == 0.0)
        #expect(mockManager.mockIsCapturingMediaKeys == false)
        #expect(mockManager.shouldCaptureMediaKeys == true)
    }
    
    // MARK: - MockMediaKeyManager Multiple Key Types Tests
    
    @Test("MockMediaKeyManager handles all media key types")
    @MainActor
    func mockHandlesAllMediaKeyTypes() async throws {
        let mockManager = MockMediaKeyManager()
        let receivedKeys = MediaKeyTestBox<[MediaKey]>([])
        
        try await mockManager.startMediaKeyCapture { key in
            receivedKeys.value.append(key)
        }
        
        for key in MediaKey.allCases {
            mockManager.simulateMediaKey(key)
        }
        
        #expect(receivedKeys.value.count == MediaKey.allCases.count)
        for key in MediaKey.allCases {
            #expect(receivedKeys.value.contains(key))
        }
    }
    
    // MARK: - shouldCaptureMediaKeys Tests
    
    @Test("MockMediaKeyManager shouldCaptureMediaKeys defaults to true")
    @MainActor
    func mockShouldCaptureMediaKeysDefaultsToTrue() {
        let mockManager = MockMediaKeyManager()
        #expect(mockManager.shouldCaptureMediaKeys == true)
    }
    
    @Test("MockMediaKeyManager shouldCaptureMediaKeys can be set")
    @MainActor
    func mockShouldCaptureMediaKeysCanBeSet() {
        let mockManager = MockMediaKeyManager()
        mockManager.shouldCaptureMediaKeys = false
        #expect(mockManager.shouldCaptureMediaKeys == false)
        mockManager.shouldCaptureMediaKeys = true
        #expect(mockManager.shouldCaptureMediaKeys == true)
    }
}
