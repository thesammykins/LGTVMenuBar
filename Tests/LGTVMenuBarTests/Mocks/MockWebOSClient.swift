import Foundation
@testable import LGTVMenuBar

/// Mock implementation of WebOSClientProtocol for testing
@MainActor
final class MockWebOSClient: WebOSClientProtocol {
    
    // MARK: - Configuration
    
    /// Whether connect should throw an error
    var shouldThrowOnConnect = false
    
    /// Whether sendCommand should throw an error
    var shouldThrowOnSendCommand = false
    
    /// Error to throw when configured to throw
    var errorToThrow: Error = MockWebOSClientError.connectionFailed("Mock error")
    
    /// Simulated connection state
    var mockConnectionState: ConnectionState = .disconnected
    
    /// Simulated delay for async operations (in seconds)
    var asyncDelay: TimeInterval = 0.0
    
    // MARK: - Call History
    
    /// History of connect calls with configurations
    private(set) var connectCalls: [(configuration: TVConfiguration, timestamp: Date)] = []
    
    /// History of disconnect calls
    private(set) var disconnectCalls: [Date] = []
    
    /// History of sendCommand calls
    private(set) var sendCommandCalls: [(command: WebOSCommand, timestamp: Date)] = []
    
    /// Stored callbacks
    private var stateChangeCallback: (@Sendable (ConnectionState) -> Void)?
    private var capabilityCallback: (@Sendable (TVCapabilities) -> Void)?
    private var inputChangeCallback: (@Sendable (TVInputType) -> Void)?
    private var volumeChangeCallback: (@Sendable (Int, Bool) -> Void)?
    private var inputListCallback: (@Sendable ([String: String]) -> Void)?
    private var soundOutputChangeCallback: (@Sendable (TVSoundOutput) -> Void)?
    private var diagnosticPayloadCallback: ((String, String) -> Void)?
    
    // MARK: - WebOSClientProtocol Implementation
    
    var connectionState: ConnectionState {
        return mockConnectionState
    }
    
    func connect(to configuration: TVConfiguration, stateChangeCallback: @escaping @Sendable (ConnectionState) -> Void) async throws {
        connectCalls.append((configuration: configuration, timestamp: Date()))
        self.stateChangeCallback = stateChangeCallback
        
        if shouldThrowOnConnect {
            throw errorToThrow
        }
        
        // Simulate async delay if configured
        if asyncDelay > 0 {
            try await Task.sleep(for: .seconds(asyncDelay))
        }
        
        mockConnectionState = .connected
        stateChangeCallback(.connected)
    }
    
    func disconnect() {
        disconnectCalls.append(Date())
        mockConnectionState = .disconnected
        stateChangeCallback?(.disconnected)
    }
    
    func sendCommand(_ command: WebOSCommand) async throws {
        sendCommandCalls.append((command: command, timestamp: Date()))
        
        if shouldThrowOnSendCommand {
            throw errorToThrow
        }
        
        // Simulate async delay if configured
        if asyncDelay > 0 {
            try await Task.sleep(for: .seconds(asyncDelay))
        }
    }
    
    func setCapabilityCallback(_ callback: @escaping @Sendable (TVCapabilities) -> Void) {
        self.capabilityCallback = callback
    }
    
    func setInputChangeCallback(_ callback: @escaping @Sendable (TVInputType) -> Void) {
        self.inputChangeCallback = callback
    }
    
    func setVolumeChangeCallback(_ callback: @escaping @Sendable (Int, Bool) -> Void) {
        self.volumeChangeCallback = callback
    }
    
    func setInputListCallback(_ callback: @escaping @Sendable ([String: String]) -> Void) {
        self.inputListCallback = callback
    }
    
    func setSoundOutputChangeCallback(_ callback: @escaping @Sendable (TVSoundOutput) -> Void) {
        self.soundOutputChangeCallback = callback
    }

    func setDiagnosticPayloadCallback(_ callback: @escaping (String, String) -> Void) {
        self.diagnosticPayloadCallback = callback
    }
    
    // MARK: - Test Helpers
    
    /// Reset all mock state
    func reset() {
        connectCalls.removeAll()
        disconnectCalls.removeAll()
        sendCommandCalls.removeAll()
        
        shouldThrowOnConnect = false
        shouldThrowOnSendCommand = false
        errorToThrow = MockWebOSClientError.connectionFailed("Mock error")
        mockConnectionState = .disconnected
        asyncDelay = 0.0
        
        stateChangeCallback = nil
        capabilityCallback = nil
        inputChangeCallback = nil
        volumeChangeCallback = nil
        inputListCallback = nil
        soundOutputChangeCallback = nil
        diagnosticPayloadCallback = nil
    }
    
    /// Get number of times connect was called
    var connectCallCount: Int {
        return connectCalls.count
    }
    
    /// Get number of times disconnect was called
    var disconnectCallCount: Int {
        return disconnectCalls.count
    }
    
    /// Get number of times sendCommand was called
    var sendCommandCallCount: Int {
        return sendCommandCalls.count
    }
    
    /// Get timestamp of most recent connect call
    var lastConnectCall: Date? {
        return connectCalls.last?.timestamp
    }
    
    /// Get timestamp of most recent disconnect call
    var lastDisconnectCall: Date? {
        return disconnectCalls.last
    }
    
    /// Get timestamp of most recent sendCommand call
    var lastSendCommandCall: Date? {
        return sendCommandCalls.last?.timestamp
    }
    
    /// Simulate connection state change
    func simulateConnectionStateChange(to state: ConnectionState) {
        mockConnectionState = state
        stateChangeCallback?(state)
    }
    
    /// Simulate capability update
    func simulateCapabilityUpdate(_ capabilities: TVCapabilities) {
        capabilityCallback?(capabilities)
    }
    
    /// Simulate input change
    func simulateInputChange(_ inputType: TVInputType) {
        inputChangeCallback?(inputType)
    }
    
    /// Simulate volume change
    func simulateVolumeChange(volume: Int, isMuted: Bool) {
        volumeChangeCallback?(volume, isMuted)
    }
    
    /// Simulate input list update
    func simulateInputListUpdate(_ inputIcons: [String: String]) {
        inputListCallback?(inputIcons)
    }
    
    /// Simulate sound output change
    func simulateSoundOutputChange(_ soundOutput: TVSoundOutput) {
        soundOutputChangeCallback?(soundOutput)
    }
    
    /// Check if connect was called within the specified time interval
    func wasConnectCalledRecently(within interval: TimeInterval) -> Bool {
        guard let lastCall = lastConnectCall else { return false }
        return Date().timeIntervalSince(lastCall) <= interval
    }
    
    /// Check if disconnect was called within the specified time interval
    func wasDisconnectCalledRecently(within interval: TimeInterval) -> Bool {
        guard let lastCall = lastDisconnectCall else { return false }
        return Date().timeIntervalSince(lastCall) <= interval
    }
}

/// Mock WebOSClient errors for testing
enum MockWebOSClientError: Error, LocalizedError {
    case connectionFailed(String)
    case commandFailed(String)
    case invalidResponse
    case timeout
    
    var errorDescription: String? {
        switch self {
        case .connectionFailed(let message):
            return "Connection failed: \(message)"
        case .commandFailed(let command):
            return "Command failed: \(command)"
        case .invalidResponse:
            return "Invalid response from TV"
        case .timeout:
            return "Operation timed out"
        }
    }
}
