import Foundation
@testable import LGTVMenuBar

/// Mock implementation of DiagnosticLoggerProtocol for testing
@MainActor
final class MockDiagnosticLogger: DiagnosticLoggerProtocol, Sendable {
    
    // MARK: - Configuration
    
    /// Whether logging is enabled
    private(set) var isEnabled: Bool = false
    
    /// Whether debug mode is active
    private(set) var isDebugMode: Bool = false
    
    // MARK: - Call History
    
    /// History of all log() calls
    struct LogCall: Sendable {
        let level: String
        let category: String
        let message: String
        let metadata: [String: String]?
        let timestamp: Date
    }
    
    private(set) var logCalls: [LogCall] = []
    private(set) var clearCalls: [Date] = []
    private(set) var enableCalls: [Date] = []
    private(set) var disableCalls: [Date] = []
    private(set) var setDebugModeCalls: [(enabled: Bool, timestamp: Date)] = []
    private(set) var exportJSONCalls: [Date] = []
    private(set) var exportPlainTextCalls: [Date] = []
    
    // MARK: - Mock State
    
    /// In-memory storage for logged entries (simplified)
    private var entries: [LogCall] = []
    
    var entryCount: Int {
        entries.count
    }
    
    var recentEntryCount: Int {
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        return entries.filter { $0.timestamp >= cutoff }.count
    }
    
    // MARK: - DiagnosticLoggerProtocol Implementation
    
    func log(level: String, category: String, message: String, metadata: [String: String]?) {
        let call = LogCall(
            level: level,
            category: category,
            message: message,
            metadata: metadata,
            timestamp: Date()
        )
        
        logCalls.append(call)
        
        // Simple filtering logic for testing
        if isEnabled {
            if isDebugMode {
                entries.append(call)
            } else {
                // Only capture warning and error in normal mode
                if level == "warning" || level == "error" {
                    entries.append(call)
                }
            }
        }
    }
    
    func exportJSON() throws -> Data {
        exportJSONCalls.append(Date())
        
        // Minimal mock JSON export
        let exportData: [String: Any] = [
            "export_time": ISO8601DateFormatter().string(from: Date()),
            "app_version": "1.0.4",
            "system_version": "Mock System",
            "entry_count": entries.count,
            "entries": entries.map { entry -> [String: Any] in
                var dict: [String: Any] = [
                    "timestamp": ISO8601DateFormatter().string(from: entry.timestamp),
                    "level": entry.level,
                    "category": entry.category,
                    "message": entry.message
                ]
                if let metadata = entry.metadata {
                    dict["metadata"] = metadata
                }
                return dict
            }
        ]
        
        return try JSONSerialization.data(withJSONObject: exportData, options: .prettyPrinted)
    }
    
    func exportPlainText() -> String {
        exportPlainTextCalls.append(Date())
        
        var output = """
        LGTVMenuBar Diagnostic Log (Mock)
        Entry Count: \(entries.count)
        
        """
        
        for entry in entries {
            output += "[\(entry.level.uppercased())] [\(entry.category)] \(entry.message)\n"
            if let metadata = entry.metadata, !metadata.isEmpty {
                output += "  Metadata: \(metadata)\n"
            }
        }
        
        return output
    }
    
    func clear() {
        clearCalls.append(Date())
        entries.removeAll()
    }
    
    func enable() {
        enableCalls.append(Date())
        isEnabled = true
    }
    
    func disable() {
        disableCalls.append(Date())
        isEnabled = false
    }
    
    func setDebugMode(_ enabled: Bool) {
        setDebugModeCalls.append((enabled: enabled, timestamp: Date()))
        isDebugMode = enabled
    }
    
    // MARK: - Test Helpers
    
    /// Reset all mock state and call history
    func reset() {
        logCalls.removeAll()
        clearCalls.removeAll()
        enableCalls.removeAll()
        disableCalls.removeAll()
        setDebugModeCalls.removeAll()
        exportJSONCalls.removeAll()
        exportPlainTextCalls.removeAll()
        
        entries.removeAll()
        isEnabled = false
        isDebugMode = false
    }
    
    /// Get call count helpers
    var logCallCount: Int { logCalls.count }
    var clearCallCount: Int { clearCalls.count }
    var enableCallCount: Int { enableCalls.count }
    var disableCallCount: Int { disableCalls.count }
    var setDebugModeCallCount: Int { setDebugModeCalls.count }
    var exportJSONCallCount: Int { exportJSONCalls.count }
    var exportPlainTextCallCount: Int { exportPlainTextCalls.count }
    
    /// Get logs by level
    func getLogs(level: String) -> [LogCall] {
        return logCalls.filter { $0.level == level }
    }
    
    /// Get logs by category
    func getLogs(category: String) -> [LogCall] {
        return logCalls.filter { $0.category == category }
    }
    
    /// Check if a specific message was logged
    func wasLogged(message: String) -> Bool {
        return logCalls.contains { $0.message == message }
    }
    
    /// Check if a message with specific level and category was logged
    func wasLogged(level: String, category: String, message: String) -> Bool {
        return logCalls.contains { $0.level == level && $0.category == category && $0.message == message }
    }
    
    /// Get most recent log call
    var lastLogCall: LogCall? {
        return logCalls.last
    }
}
