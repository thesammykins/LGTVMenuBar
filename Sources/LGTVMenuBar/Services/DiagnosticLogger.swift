import Foundation

/// Diagnostic logger for capturing application events and errors
@MainActor
final class DiagnosticLogger: DiagnosticLoggerProtocol {
    
    // MARK: - Types
    
    /// A single log entry with timestamp, level, category, message, and optional metadata
    struct LogEntry: Sendable {
        let timestamp: Date
        let level: String
        let category: String
        let message: String
        let metadata: [String: String]?
    }
    
    // MARK: - Properties
    
    private(set) var isEnabled: Bool = false
    private(set) var isDebugMode: Bool = false
    
    private var entries: [LogEntry] = []
    private let maxEntries = 1000
    private let entryLifetime: TimeInterval = 24 * 60 * 60 // 24 hours
    
    var entryCount: Int {
        entries.count
    }
    
    var recentEntryCount: Int {
        let cutoff = Date().addingTimeInterval(-entryLifetime)
        return entries.filter { $0.timestamp >= cutoff }.count
    }
    
    // MARK: - Initialization
    
    init() {}
    
    // MARK: - Public Methods
    
    func log(level: String, category: String, message: String, metadata: [String: String]? = nil) {
        guard isEnabled else { return }
        
        // Level filtering
        if !isDebugMode {
            // Only capture warning and error in normal mode
            guard level == "warning" || level == "error" else { return }
        }
        
        // Purge old entries
        purgeOldEntries()
        
        // Create and add new entry
        let entry = LogEntry(
            timestamp: Date(),
            level: level,
            category: category,
            message: message,
            metadata: metadata
        )
        
        entries.append(entry)
        
        // Enforce max entries (ring buffer behavior)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }
    
    func exportJSON() throws -> Data {
        let cutoff = Date().addingTimeInterval(-entryLifetime)
        let recentEntries = entries.filter { $0.timestamp >= cutoff }
        
        // Build export structure
        let exportData: [String: Any] = [
            "export_time": ISO8601DateFormatter().string(from: Date()),
            "app_version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown",
            "system_version": ProcessInfo.processInfo.operatingSystemVersionString,
            "entry_count": recentEntries.count,
            "entries": recentEntries.map { entry -> [String: Any] in
                var entryDict: [String: Any] = [
                    "timestamp": ISO8601DateFormatter().string(from: entry.timestamp),
                    "level": entry.level,
                    "category": entry.category,
                    "message": entry.message
                ]
                if let metadata = entry.metadata {
                    entryDict["metadata"] = metadata
                }
                return entryDict
            }
        ]
        
        return try JSONSerialization.data(withJSONObject: exportData, options: .prettyPrinted)
    }
    
    func exportPlainText() -> String {
        let cutoff = Date().addingTimeInterval(-entryLifetime)
        let recentEntries = entries.filter { $0.timestamp >= cutoff }
        
        var output = """
        LGTVMenuBar Diagnostic Log
        Export Time: \(formatDate(Date()))
        App Version: \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown")
        System Version: \(ProcessInfo.processInfo.operatingSystemVersionString)
        Entry Count: \(recentEntries.count)
        
        ================================================================================
        
        """
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        
        for entry in recentEntries {
            let timestamp = dateFormatter.string(from: entry.timestamp)
            let levelPadded = entry.level.uppercased().padding(toLength: 7, withPad: " ", startingAt: 0)
            output += "[\(timestamp)] [\(levelPadded)] [\(entry.category)]\n"
            output += "  \(entry.message)\n"
            
            if let metadata = entry.metadata, !metadata.isEmpty {
                output += "  Metadata:\n"
                for (key, value) in metadata.sorted(by: { $0.key < $1.key }) {
                    output += "    \(key): \(value)\n"
                }
            }
            output += "\n"
        }
        
        return output
    }
    
    func clear() {
        entries.removeAll()
    }
    
    func enable() {
        isEnabled = true
    }
    
    func disable() {
        isEnabled = false
    }
    
    func setDebugMode(_ enabled: Bool) {
        isDebugMode = enabled
    }
    
    // MARK: - Private Methods
    
    private func purgeOldEntries() {
        let cutoff = Date().addingTimeInterval(-entryLifetime)
        entries.removeAll { $0.timestamp < cutoff }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return formatter.string(from: date)
    }
}
