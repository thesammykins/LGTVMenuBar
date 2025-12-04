import Foundation

/// Protocol defining diagnostic logging capabilities for debugging and troubleshooting
@MainActor
public protocol DiagnosticLoggerProtocol: Sendable {
    /// Whether logging is currently enabled
    var isEnabled: Bool { get }
    
    /// Whether debug mode is active (captures all log levels)
    var isDebugMode: Bool { get }
    
    /// Total number of log entries in the buffer
    var entryCount: Int { get }
    
    /// Number of log entries from the last 24 hours
    var recentEntryCount: Int { get }
    
    /// Log a message with specified level, category, and optional metadata
    /// - Parameters:
    ///   - level: Log level (debug, info, warning, error)
    ///   - category: Category identifier for the log entry
    ///   - message: The log message
    ///   - metadata: Optional key-value pairs for additional context
    func log(level: String, category: String, message: String, metadata: [String: String]?)
    
    /// Export log entries as JSON data
    /// - Returns: JSON data containing metadata and log entries
    func exportJSON() throws -> Data
    
    /// Export log entries as plain text
    /// - Returns: Human-readable formatted string of log entries
    func exportPlainText() -> String
    
    /// Remove all log entries from the buffer
    func clear()
    
    /// Enable diagnostic logging
    func enable()
    
    /// Disable diagnostic logging
    func disable()
    
    /// Toggle debug mode
    /// - Parameter enabled: Whether debug mode should be enabled
    func setDebugMode(_ enabled: Bool)
}
