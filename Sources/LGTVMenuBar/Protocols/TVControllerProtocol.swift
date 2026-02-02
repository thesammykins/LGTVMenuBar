import Foundation

/// Protocol for TV controller operations
@MainActor
public protocol TVControllerProtocol: Sendable {
    // MARK: - Published State
    
    var configuration: TVConfiguration? { get }
    var connectionState: ConnectionState { get }
    var capabilities: TVCapabilities? { get }
    var volume: Int { get }
    var isMuted: Bool { get }
    var currentInput: TVInputType? { get }
    var soundOutput: TVSoundOutput { get }
    var isMediaKeyControlEnabled: Bool { get set }
    
    /// Diagnostic logger for troubleshooting and log export
    var diagnosticLogger: DiagnosticLoggerProtocol { get }
    
    // MARK: - Configuration
    
    func saveConfiguration(_ config: TVConfiguration) throws
    func clearConfiguration() throws
    
    // MARK: - Connection
    
    func connect() async throws
    func disconnect()
    func autoConnectOnStartup() async
    func wake() async throws
    
    // MARK: - Power Control
    
    func powerOff() async throws
    func screenOn() async throws
    func screenOff() async throws
    
    // MARK: - Volume Control
    
    func volumeUp() async throws
    func volumeDown() async throws
    func setVolume(_ level: Int) async throws
    func toggleMute() async throws
    
    // MARK: - Input Control
    
    func switchInput(_ input: TVInputType) async throws
    func setSoundOutput(_ output: TVSoundOutput) async throws
    
    // MARK: - Launch at Login
    
    func isLaunchAtLoginEnabled() async throws -> Bool
    func setLaunchAtLogin(_ enabled: Bool) async throws
}
