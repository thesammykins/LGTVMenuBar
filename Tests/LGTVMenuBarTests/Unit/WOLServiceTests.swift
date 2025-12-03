import Testing
import Foundation
@testable import LGTVMenuBar

/// Test suite for WOLService and WOLError
/// 
/// Note: Since WOLService requires network access for actual WOL packets,
/// most tests use MockWOLService. WOLError tests verify error handling behavior.
@Suite("WOLService Tests")
struct WOLServiceTests {
    
    // MARK: - WOLError Tests
    
    @Test("invalidMACAddress error provides localized description")
    func invalidMACAddressErrorDescription() {
        let error = WOLError.invalidMACAddress("12:34:56")
        #expect(error.errorDescription?.contains("Invalid MAC address") == true)
        #expect(error.errorDescription?.contains("12:34:56") == true)
    }
    
    @Test("invalidMACAddress error with details includes reason")
    func invalidMACAddressErrorWithDetails() {
        let error = WOLError.invalidMACAddress("12:34:56", "Too short")
        #expect(error.errorDescription?.contains("Too short") == true)
    }
    
    @Test("packetCreationFailed error provides localized description")
    func packetCreationFailedErrorDescription() {
        let error = WOLError.packetCreationFailed("Invalid packet size")
        #expect(error.errorDescription?.contains("Failed to create magic packet") == true)
        #expect(error.errorDescription?.contains("Invalid packet size") == true)
    }
    
    @Test("networkError wraps underlying error")
    func networkErrorWrapsUnderlyingError() {
        let underlyingError = NSError(domain: "TestDomain", code: 123, userInfo: [NSLocalizedDescriptionKey: "Test network failure"])
        let error = WOLError.networkError(underlyingError)
        #expect(error.errorDescription?.contains("Network error") == true)
    }
    
    @Test("broadcastFailed error provides localized description")
    func broadcastFailedErrorDescription() {
        let error = WOLError.broadcastFailed
        #expect(error.errorDescription?.contains("Failed to broadcast wake packet") == true)
    }
    
    @Test("WOLError conforms to Error protocol")
    func wolErrorConformsToError() {
        let error: Error = WOLError.broadcastFailed
        #expect(error is WOLError)
    }
    
    @Test("WOLError conforms to LocalizedError protocol")
    func wolErrorConformsToLocalizedError() {
        let error: LocalizedError = WOLError.broadcastFailed
        #expect(error.errorDescription != nil)
    }
    
    // MARK: - MockWOLService Tests
    
    @Test("MockWOLService tracks wake calls")
    func mockWOLServiceTracksWakeCalls() async throws {
        let mockService = MockWOLService()
        
        try await mockService.sendWakeOnLAN(macAddress: "AA:BB:CC:DD:EE:FF")
        try await mockService.sendWakeOnLAN(macAddress: "11:22:33:44:55:66")
        
        #expect(mockService.wakeCalls.count == 2)
        #expect(mockService.wakeCalls[0] == "AA:BB:CC:DD:EE:FF")
        #expect(mockService.wakeCalls[1] == "11:22:33:44:55:66")
    }
    
    @Test("MockWOLService sendWakeRequest uses configuration macAddress")
    func mockWOLServiceSendWakeRequest() async throws {
        let mockService = MockWOLService()
        let config = TVConfiguration(
            name: "Test TV",
            ipAddress: "192.168.1.100",
            macAddress: "AA:BB:CC:DD:EE:FF"
        )
        
        try await mockService.sendWakeRequest(to: config)
        
        #expect(mockService.wakeCalls.count == 1)
        #expect(mockService.wakeCalls[0] == "AA:BB:CC:DD:EE:FF")
    }
    
    @Test("MockWOLService can be configured to throw errors")
    func mockWOLServiceThrowsConfiguredError() async {
        let mockService = MockWOLService()
        mockService.shouldThrowOnWake = true
        
        await #expect(throws: Error.self) {
            try await mockService.sendWakeOnLAN(macAddress: "AA:BB:CC:DD:EE:FF")
        }
    }
    
    @Test("MockWOLService throws on invalid MAC when configured")
    func mockWOLServiceThrowsOnInvalidMAC() async {
        let mockService = MockWOLService()
        mockService.shouldSucceedWake = false
        
        await #expect(throws: Error.self) {
            try await mockService.sendWakeOnLAN(macAddress: "invalid")
        }
    }
    
    @Test("MockWOLService reset clears all state")
    func mockWOLServiceResetClearsState() async throws {
        let mockService = MockWOLService()
        
        // Configure mock
        mockService.shouldThrowOnWake = true
        mockService.wakeDelay = 1.0
        
        // Make some calls
        try? await mockService.sendWakeOnLAN(macAddress: "AA:BB:CC:DD:EE:FF")
        
        // Reset
        mockService.reset()
        
        // Verify reset
        #expect(mockService.wakeCalls.isEmpty)
        #expect(mockService.shouldThrowOnWake == false)
        #expect(mockService.shouldSucceedWake == true)
        #expect(mockService.wakeDelay == 0.0)
    }
    
    @Test("MockWOLService wakeCallCount returns correct count for specific MAC")
    func mockWOLServiceWakeCallCountForMAC() async throws {
        let mockService = MockWOLService()
        
        try await mockService.sendWakeOnLAN(macAddress: "AA:BB:CC:DD:EE:FF")
        try await mockService.sendWakeOnLAN(macAddress: "11:22:33:44:55:66")
        try await mockService.sendWakeOnLAN(macAddress: "AA:BB:CC:DD:EE:FF")
        
        #expect(mockService.wakeCallCount(for: "AA:BB:CC:DD:EE:FF") == 2)
        #expect(mockService.wakeCallCount(for: "11:22:33:44:55:66") == 1)
        #expect(mockService.wakeCallCount(for: "00:00:00:00:00:00") == 0)
    }
    
    @Test("MockWOLService tracks timestamps for wake calls")
    func mockWOLServiceTracksTimestamps() async throws {
        let mockService = MockWOLService()
        
        let beforeCall = Date()
        try await mockService.sendWakeOnLAN(macAddress: "AA:BB:CC:DD:EE:FF")
        let afterCall = Date()
        
        let lastCall = mockService.lastWakeCall(for: "AA:BB:CC:DD:EE:FF")
        #expect(lastCall != nil)
        
        if let timestamp = lastCall {
            #expect(timestamp >= beforeCall)
            #expect(timestamp <= afterCall)
        }
    }
    
    @Test("MockWOLService wasWakeCalledRecently returns true for recent calls")
    func mockWOLServiceWasCalledRecently() async throws {
        let mockService = MockWOLService()
        
        try await mockService.sendWakeOnLAN(macAddress: "AA:BB:CC:DD:EE:FF")
        
        #expect(mockService.wasWakeCalledRecently(for: "AA:BB:CC:DD:EE:FF", within: 5.0) == true)
        #expect(mockService.wasWakeCalledRecently(for: "11:22:33:44:55:66", within: 5.0) == false)
    }
    
    @Test("MockWOLService allWakeCallsSorted returns calls in order")
    func mockWOLServiceAllCallsSorted() async throws {
        let mockService = MockWOLService()
        
        try await mockService.sendWakeOnLAN(macAddress: "AA:BB:CC:DD:EE:FF")
        try await mockService.sendWakeOnLAN(macAddress: "11:22:33:44:55:66")
        
        let sortedCalls = mockService.allWakeCallsSorted()
        #expect(sortedCalls.count == 2)
        #expect(sortedCalls[0].macAddress == "AA:BB:CC:DD:EE:FF")
        #expect(sortedCalls[1].macAddress == "11:22:33:44:55:66")
        #expect(sortedCalls[0].timestamp <= sortedCalls[1].timestamp)
    }
    
    @Test("MockWOLService respects configured delay")
    func mockWOLServiceRespectsDelay() async throws {
        let mockService = MockWOLService()
        mockService.wakeDelay = 0.1
        
        let startTime = Date()
        try await mockService.sendWakeOnLAN(macAddress: "AA:BB:CC:DD:EE:FF")
        let endTime = Date()
        
        let elapsed = endTime.timeIntervalSince(startTime)
        #expect(elapsed >= 0.09) // Allow small margin for timing
    }
}
