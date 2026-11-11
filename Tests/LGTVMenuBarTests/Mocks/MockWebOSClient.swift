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

    /// Whether command failures should transition the simulated connection to an error state.
    var transitionToErrorOnCommandFailure = false
    
    /// Error to throw when configured to throw
    var errorToThrow: Error = MockWebOSClientError.connectionFailed("Mock error")

    /// Sequence of connect results to return on successive connect attempts.
    var connectResults: [Result<Void, Error>] = []

    /// Optional state to publish when a queued connect failure is emitted.
    var connectionStateAfterConnectFailure: ConnectionState?

    /// Sequence of power status results to return on successive power checks.
    var powerStatusResults: [Result<TVPowerStatus, Error>] = []

    /// Default power status when no explicit result is queued.
    var mockPowerStatus = TVPowerStatus(state: "Active")
    
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

    /// History of power status requests
    private(set) var getPowerStatusCalls: [Date] = []
    
    /// Stored callbacks
    private var stateChangeCallback: (@Sendable (ConnectionState) -> Void)?
    private var capabilityCallback: (@Sendable (TVCapabilities) -> Void)?
    private var inputChangeCallback: (@Sendable (TVInputType) -> Void)?
    private var volumeChangeCallback: (@Sendable (Int, Bool) -> Void)?
    private var inputListCallback: (@Sendable ([String: String]) -> Void)?
    private var soundOutputChangeCallback: (@Sendable (TVSoundOutput) -> Void)?
    private var powerStateChangeCallback: (@Sendable (TVPowerStatus) -> Void)?
    private var diagnosticPayloadCallback: ((String, String) -> Void)?
    private var foregroundChangeCallback: (@Sendable (TVForeground) -> Void)?
    private var logCallback: ((String, String, [String: String]) -> Void)?

    /// History of raw SSAP requests
    private(set) var requestCalls: [(uri: String, payload: [String: Any]?)] = []

    /// Replies for raw requests, keyed by URI. Missing URIs get an empty successful reply.
    var requestReplies: [String: Result<SSAPReply, Error>] = [:]

    /// Foreground to report when the controller asks what is in front.
    var foregroundOnQuery: TVForeground?

    /// Commands the TV rejects, keyed by kind.
    enum CommandKind: Hashable { case screenOn, setDeviceInfo }
    var commandErrors: [CommandKind: Error] = [:]

    /// Runs after a command is recorded, before it returns. For interleaving TV updates.
    var onSendCommand: ((WebOSCommand) -> Void)?
    
    // MARK: - WebOSClientProtocol Implementation
    
    var connectionState: ConnectionState {
        return mockConnectionState
    }
    
    func connect(to configuration: TVConfiguration, stateChangeCallback: @escaping @Sendable (ConnectionState) -> Void) async throws {
        connectCalls.append((configuration: configuration, timestamp: Date()))
        self.stateChangeCallback = stateChangeCallback

        if !connectResults.isEmpty {
            let result = connectResults.removeFirst()

            if asyncDelay > 0 {
                try await Task.sleep(for: .seconds(asyncDelay))
            }

            switch result {
            case .success:
                mockConnectionState = .connected
                stateChangeCallback(.connected)
            case .failure(let error):
                let failureState = connectionStateAfterConnectFailure ?? .error(error)
                mockConnectionState = failureState
                stateChangeCallback(failureState)
                throw error
            }
            return
        }
        
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
            transitionToErrorIfNeeded(errorToThrow)
            throw errorToThrow
        }
        
        // Simulate async delay if configured
        if asyncDelay > 0 {
            try await Task.sleep(for: .seconds(asyncDelay))
        }

        onSendCommand?(command)
        if case .screenOn = command, let error = commandErrors[.screenOn] {
            throw error
        }
        if case .setDeviceInfo = command, let error = commandErrors[.setDeviceInfo] {
            throw error
        }

        if case .getCurrentForegroundAppInfo = command, let foregroundOnQuery {
            foregroundChangeCallback?(foregroundOnQuery)
        }
    }

    func request(uri: String, payload: [String: Any]?) async throws -> SSAPReply {
        requestCalls.append((uri: uri, payload: payload))
        if let result = requestReplies[uri] {
            return try result.get()
        }
        if shouldThrowOnSendCommand {
            transitionToErrorIfNeeded(errorToThrow)
            throw errorToThrow
        }
        return SSAPReply()
    }

    func setForegroundChangeCallback(_ callback: @escaping @Sendable (TVForeground) -> Void) {
        self.foregroundChangeCallback = callback
    }

    func setLogCallback(_ callback: @escaping (String, String, [String: String]) -> Void) {
        self.logCallback = callback
    }

    /// Simulate the TV bringing an app or input to the front.
    func simulateForegroundChange(_ foreground: TVForeground) {
        foregroundChangeCallback?(foreground)
    }

    func getPowerStatus() async throws -> TVPowerStatus {
        getPowerStatusCalls.append(Date())

        if !powerStatusResults.isEmpty {
            let result = powerStatusResults.removeFirst()

            if asyncDelay > 0 {
                try await Task.sleep(for: .seconds(asyncDelay))
            }

            switch result {
            case .success(let status):
                return status
            case .failure(let error):
                transitionToErrorIfNeeded(error)
                throw error
            }
        }

        if shouldThrowOnSendCommand {
            transitionToErrorIfNeeded(errorToThrow)
            throw errorToThrow
        }

        if asyncDelay > 0 {
            try await Task.sleep(for: .seconds(asyncDelay))
        }

        return mockPowerStatus
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

    func setPowerStateChangeCallback(_ callback: @escaping @Sendable (TVPowerStatus) -> Void) {
        self.powerStateChangeCallback = callback
    }

    func simulatePowerStateChange(_ status: TVPowerStatus) {
        powerStateChangeCallback?(status)
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
        getPowerStatusCalls.removeAll()
        requestCalls.removeAll()
        requestReplies.removeAll()
        foregroundOnQuery = nil
        commandErrors.removeAll()
        onSendCommand = nil
        
        shouldThrowOnConnect = false
        shouldThrowOnSendCommand = false
        transitionToErrorOnCommandFailure = false
        errorToThrow = MockWebOSClientError.connectionFailed("Mock error")
        connectResults.removeAll()
        connectionStateAfterConnectFailure = nil
        powerStatusResults.removeAll()
        mockPowerStatus = TVPowerStatus(state: "Active")
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

    var getPowerStatusCallCount: Int {
        return getPowerStatusCalls.count
    }

    private func transitionToErrorIfNeeded(_ error: Error) {
        guard transitionToErrorOnCommandFailure else { return }
        mockConnectionState = .error(error)
        stateChangeCallback?(.error(error))
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

    var lastGetPowerStatusCall: Date? {
        return getPowerStatusCalls.last
    }
    
    /// Simulate connection state change
    func simulateConnectionStateChange(to state: ConnectionState) {
        mockConnectionState = state
        stateChangeCallback?(state)
    }

    /// Emit a callback without changing the mock's current state.
    func emitStaleConnectionStateCallback(_ state: ConnectionState) {
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
