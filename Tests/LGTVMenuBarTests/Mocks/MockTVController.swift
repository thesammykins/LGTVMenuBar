import Foundation
@testable import LGTVMenuBar

/// Mock implementation of TVControllerProtocol for testing
@MainActor
final class MockTVController: TVControllerProtocol, Sendable {
    
    // MARK: - Configuration
    
    /// Whether operations should throw errors
    var shouldThrowError = false
    
    /// Error to throw when configured to throw
    var errorToThrow: Error = LGTVError.tvNotFound
    
    /// Simulated delay for async operations (in seconds)
    var operationDelay: TimeInterval = 0.0
    
    // MARK: - Call History
    
    /// History of saveConfiguration calls
    private(set) var saveConfigurationCalls: [(config: TVConfiguration, timestamp: Date)] = []
    
    /// History of clearConfiguration calls
    private(set) var clearConfigurationCalls: [Date] = []
    
    /// History of connect calls
    private(set) var connectCalls: [Date] = []
    
    /// History of autoConnectOnStartup calls
    private(set) var autoConnectOnStartupCalls: [Date] = []
    
    /// History of disconnect calls
    private(set) var disconnectCalls: [Date] = []
    
    /// History of wake calls
    private(set) var wakeCalls: [Date] = []
    
    /// History of powerOff calls
    private(set) var powerOffCalls: [Date] = []
    
    /// History of screenOn calls
    private(set) var screenOnCalls: [Date] = []
    
    /// History of screenOff calls
    private(set) var screenOffCalls: [Date] = []
    
    /// History of volumeUp calls
    private(set) var volumeUpCalls: [Date] = []
    
    /// History of volumeDown calls
    private(set) var volumeDownCalls: [Date] = []
    
    /// History of setVolume calls
    private(set) var setVolumeCalls: [(level: Int, timestamp: Date)] = []
    
    /// History of toggleMute calls
    private(set) var toggleMuteCalls: [Date] = []
    
    /// History of switchInput calls
    private(set) var switchInputCalls: [(input: TVInputType, timestamp: Date)] = []
    
    /// History of isLaunchAtLoginEnabled calls
    private(set) var isLaunchAtLoginEnabledCalls: [Date] = []
    
    /// History of setLaunchAtLogin calls
    private(set) var setLaunchAtLoginCalls: [(enabled: Bool, timestamp: Date)] = []
    
    // MARK: - Mock State
    
    /// Current TV configuration
    var configuration: TVConfiguration?
    
    /// Current connection state
    var connectionState: ConnectionState = .disconnected
    
    /// TV capabilities
    var capabilities: TVCapabilities?
    
    /// Current volume level
    var volume: Int = 50
    
    /// Whether TV is muted
    var isMuted: Bool = false
    
    /// Current input
    var currentInput: TVInputType?
    
    /// Whether media key control is enabled
    var isMediaKeyControlEnabled: Bool = false
    
    /// Mock return value for isLaunchAtLoginEnabled
    var mockLaunchAtLoginEnabled: Bool = false
    
    /// Diagnostic logger for troubleshooting
    private let _diagnosticLogger: DiagnosticLoggerProtocol
    
    var diagnosticLogger: DiagnosticLoggerProtocol {
        _diagnosticLogger
    }
    
    // MARK: - Initialization
    
    init(diagnosticLogger: DiagnosticLoggerProtocol) {
        self._diagnosticLogger = diagnosticLogger
    }
    
    // MARK: - TVControllerProtocol Implementation
    
    func saveConfiguration(_ config: TVConfiguration) throws {
        saveConfigurationCalls.append((config: config, timestamp: Date()))
        
        if shouldThrowError {
            throw errorToThrow
        }
        
        self.configuration = config
    }
    
    func clearConfiguration() throws {
        clearConfigurationCalls.append(Date())
        
        if shouldThrowError {
            throw errorToThrow
        }
        
        self.configuration = nil
    }
    
    func connect() async throws {
        connectCalls.append(Date())
        
        if operationDelay > 0 {
            try await Task.sleep(for: .seconds(operationDelay))
        }
        
        if shouldThrowError {
            throw errorToThrow
        }
        
        connectionState = .connected
    }
    
    func disconnect() {
        disconnectCalls.append(Date())
        connectionState = .disconnected
    }
    
    func autoConnectOnStartup() async {
        autoConnectOnStartupCalls.append(Date())
        
        if operationDelay > 0 {
            try? await Task.sleep(for: .seconds(operationDelay))
        }
        
        // Only auto-connect if config exists and autoConnectOnLaunch is true
        guard let config = configuration, config.autoConnectOnLaunch else { return }
        
        // Simulate the retry logic (simplified for mock)
        do {
            try await connect()
        } catch {
            // Silent failure for mock
        }
    }
    
    func wake() async throws {
        wakeCalls.append(Date())
        
        if operationDelay > 0 {
            try await Task.sleep(for: .seconds(operationDelay))
        }
        
        if shouldThrowError {
            throw errorToThrow
        }
    }
    
    func powerOff() async throws {
        powerOffCalls.append(Date())
        
        if operationDelay > 0 {
            try await Task.sleep(for: .seconds(operationDelay))
        }
        
        if shouldThrowError {
            throw errorToThrow
        }
    }
    
    func screenOn() async throws {
        screenOnCalls.append(Date())
        
        if operationDelay > 0 {
            try await Task.sleep(for: .seconds(operationDelay))
        }
        
        if shouldThrowError {
            throw errorToThrow
        }
    }
    
    func screenOff() async throws {
        screenOffCalls.append(Date())
        
        if operationDelay > 0 {
            try await Task.sleep(for: .seconds(operationDelay))
        }
        
        if shouldThrowError {
            throw errorToThrow
        }
    }
    
    func volumeUp() async throws {
        volumeUpCalls.append(Date())
        
        if operationDelay > 0 {
            try await Task.sleep(for: .seconds(operationDelay))
        }
        
        if shouldThrowError {
            throw errorToThrow
        }
        
        volume = min(100, volume + 5)
    }
    
    func volumeDown() async throws {
        volumeDownCalls.append(Date())
        
        if operationDelay > 0 {
            try await Task.sleep(for: .seconds(operationDelay))
        }
        
        if shouldThrowError {
            throw errorToThrow
        }
        
        volume = max(0, volume - 5)
    }
    
    func setVolume(_ level: Int) async throws {
        setVolumeCalls.append((level: level, timestamp: Date()))
        
        if operationDelay > 0 {
            try await Task.sleep(for: .seconds(operationDelay))
        }
        
        if shouldThrowError {
            throw errorToThrow
        }
        
        volume = max(0, min(100, level))
    }
    
    func toggleMute() async throws {
        toggleMuteCalls.append(Date())
        
        if operationDelay > 0 {
            try await Task.sleep(for: .seconds(operationDelay))
        }
        
        if shouldThrowError {
            throw errorToThrow
        }
        
        isMuted.toggle()
    }
    
    func switchInput(_ input: TVInputType) async throws {
        switchInputCalls.append((input: input, timestamp: Date()))
        
        if operationDelay > 0 {
            try await Task.sleep(for: .seconds(operationDelay))
        }
        
        if shouldThrowError {
            throw errorToThrow
        }
        
        currentInput = input
    }
    
    func isLaunchAtLoginEnabled() async throws -> Bool {
        isLaunchAtLoginEnabledCalls.append(Date())
        
        if operationDelay > 0 {
            try await Task.sleep(for: .seconds(operationDelay))
        }
        
        if shouldThrowError {
            throw errorToThrow
        }
        
        return mockLaunchAtLoginEnabled
    }
    
    func setLaunchAtLogin(_ enabled: Bool) async throws {
        setLaunchAtLoginCalls.append((enabled: enabled, timestamp: Date()))
        
        if operationDelay > 0 {
            try await Task.sleep(for: .seconds(operationDelay))
        }
        
        if shouldThrowError {
            throw errorToThrow
        }
        
        mockLaunchAtLoginEnabled = enabled
    }
    
    // MARK: - Test Helpers
    
    /// Reset all mock state and call history
    func reset() {
        saveConfigurationCalls.removeAll()
        clearConfigurationCalls.removeAll()
        connectCalls.removeAll()
        autoConnectOnStartupCalls.removeAll()
        disconnectCalls.removeAll()
        wakeCalls.removeAll()
        powerOffCalls.removeAll()
        screenOnCalls.removeAll()
        screenOffCalls.removeAll()
        volumeUpCalls.removeAll()
        volumeDownCalls.removeAll()
        setVolumeCalls.removeAll()
        toggleMuteCalls.removeAll()
        switchInputCalls.removeAll()
        isLaunchAtLoginEnabledCalls.removeAll()
        setLaunchAtLoginCalls.removeAll()
        
        configuration = nil
        connectionState = .disconnected
        capabilities = nil
        volume = 50
        isMuted = false
        currentInput = nil
        isMediaKeyControlEnabled = false
        mockLaunchAtLoginEnabled = false
        
        shouldThrowError = false
        errorToThrow = LGTVError.tvNotFound
        operationDelay = 0.0
    }
    
    /// Get number of times a specific method was called
    var saveConfigurationCallCount: Int { saveConfigurationCalls.count }
    var clearConfigurationCallCount: Int { clearConfigurationCalls.count }
    var connectCallCount: Int { connectCalls.count }
    var autoConnectOnStartupCallCount: Int { autoConnectOnStartupCalls.count }
    var disconnectCallCount: Int { disconnectCalls.count }
    var wakeCallCount: Int { wakeCalls.count }
    var powerOffCallCount: Int { powerOffCalls.count }
    var screenOnCallCount: Int { screenOnCalls.count }
    var screenOffCallCount: Int { screenOffCalls.count }
    var volumeUpCallCount: Int { volumeUpCalls.count }
    var volumeDownCallCount: Int { volumeDownCalls.count }
    var setVolumeCallCount: Int { setVolumeCalls.count }
    var toggleMuteCallCount: Int { toggleMuteCalls.count }
    var switchInputCallCount: Int { switchInputCalls.count }
    var isLaunchAtLoginEnabledCallCount: Int { isLaunchAtLoginEnabledCalls.count }
    var setLaunchAtLoginCallCount: Int { setLaunchAtLoginCalls.count }
    
    /// Get timestamp of most recent call for each method
    var lastSaveConfigurationCall: Date? { saveConfigurationCalls.last?.timestamp }
    var lastClearConfigurationCall: Date? { clearConfigurationCalls.last }
    var lastConnectCall: Date? { connectCalls.last }
    var lastAutoConnectOnStartupCall: Date? { autoConnectOnStartupCalls.last }
    var lastDisconnectCall: Date? { disconnectCalls.last }
    var lastWakeCall: Date? { wakeCalls.last }
    var lastPowerOffCall: Date? { powerOffCalls.last }
    var lastScreenOnCall: Date? { screenOnCalls.last }
    var lastScreenOffCall: Date? { screenOffCalls.last }
    var lastVolumeUpCall: Date? { volumeUpCalls.last }
    var lastVolumeDownCall: Date? { volumeDownCalls.last }
    var lastSetVolumeCall: Date? { setVolumeCalls.last?.timestamp }
    var lastToggleMuteCall: Date? { toggleMuteCalls.last }
    var lastSwitchInputCall: Date? { switchInputCalls.last?.timestamp }
    var lastIsLaunchAtLoginEnabledCall: Date? { isLaunchAtLoginEnabledCalls.last }
    var lastSetLaunchAtLoginCall: Date? { setLaunchAtLoginCalls.last?.timestamp }
    
    /// Check if a method was called recently
    func wasCalledRecently(_ call: Date?, within interval: TimeInterval) -> Bool {
        guard let call = call else { return false }
        return Date().timeIntervalSince(call) <= interval
    }
    
    /// Simulate connection state change
    func simulateConnectionState(_ state: ConnectionState) {
        connectionState = state
    }
    
    /// Simulate capability update
    func simulateCapabilityUpdate(_ caps: TVCapabilities) {
        capabilities = caps
    }
    
    /// Simulate input change
    func simulateInputChange(_ input: TVInputType) {
        currentInput = input
    }
}
