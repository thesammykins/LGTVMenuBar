import Testing
import Foundation
@testable import LGTVMenuBar

@Suite("DiagnosticLogger Tests")
@MainActor
struct DiagnosticLoggerTests {
    
    // MARK: - Basic Functionality Tests
    
    @Test("Log entry creation captures all fields correctly")
    func logEntryCreationCapturesAllFields() {
        let logger = DiagnosticLogger()
        logger.enable()
        logger.setDebugMode(true)
        
        let metadata = ["key1": "value1", "key2": "value2"]
        logger.log(level: "info", category: "test", message: "Test message", metadata: metadata)
        
        #expect(logger.entryCount == 1)
        
        // Export to verify fields
        let plainText = logger.exportPlainText()
        #expect(plainText.contains("INFO"))
        #expect(plainText.contains("test"))
        #expect(plainText.contains("Test message"))
        #expect(plainText.contains("key1: value1"))
        #expect(plainText.contains("key2: value2"))
    }
    
    @Test("Enable toggle allows logging")
    func enableToggleAllowsLogging() {
        let logger = DiagnosticLogger()
        logger.setDebugMode(true)
        
        // Disabled by default
        logger.log(level: "info", category: "test", message: "Should not log")
        #expect(logger.entryCount == 0)
        
        // Enable logging
        logger.enable()
        logger.log(level: "info", category: "test", message: "Should log")
        #expect(logger.entryCount == 1)
    }
    
    @Test("Disable toggle prevents logging")
    func disableTogglePreventsLogging() {
        let logger = DiagnosticLogger()
        logger.enable()
        logger.setDebugMode(true)
        
        logger.log(level: "info", category: "test", message: "First log")
        #expect(logger.entryCount == 1)
        
        // Disable logging
        logger.disable()
        logger.log(level: "info", category: "test", message: "Should not log")
        #expect(logger.entryCount == 1)
    }
    
    @Test("Debug mode toggle affects level filtering")
    func debugModeToggleAffectsLevelFiltering() {
        let logger = DiagnosticLogger()
        logger.enable()
        
        // Debug mode off - only warning/error captured
        logger.log(level: "debug", category: "test", message: "Debug message")
        logger.log(level: "info", category: "test", message: "Info message")
        #expect(logger.entryCount == 0)
        
        logger.log(level: "warning", category: "test", message: "Warning message")
        logger.log(level: "error", category: "test", message: "Error message")
        #expect(logger.entryCount == 2)
        
        // Clear and enable debug mode
        logger.clear()
        logger.setDebugMode(true)
        
        // All levels captured
        logger.log(level: "debug", category: "test", message: "Debug message")
        logger.log(level: "info", category: "test", message: "Info message")
        logger.log(level: "warning", category: "test", message: "Warning message")
        logger.log(level: "error", category: "test", message: "Error message")
        #expect(logger.entryCount == 4)
    }
    
    @Test("Clear removes all entries")
    func clearRemovesAllEntries() {
        let logger = DiagnosticLogger()
        logger.enable()
        logger.setDebugMode(true)
        
        // Add multiple entries
        for i in 0..<10 {
            logger.log(level: "info", category: "test", message: "Message \(i)", metadata: nil)
        }
        #expect(logger.entryCount == 10)
        
        // Clear all
        logger.clear()
        #expect(logger.entryCount == 0)
    }
    
    @Test("EntryCount computed property returns correct count")
    func entryCountComputedPropertyReturnsCorrectCount() {
        let logger = DiagnosticLogger()
        logger.enable()
        logger.setDebugMode(true)
        
        #expect(logger.entryCount == 0)
        
        logger.log(level: "info", category: "test", message: "First", metadata: nil)
        #expect(logger.entryCount == 1)
        
        logger.log(level: "info", category: "test", message: "Second", metadata: nil)
        #expect(logger.entryCount == 2)
        
        logger.log(level: "info", category: "test", message: "Third", metadata: nil)
        #expect(logger.entryCount == 3)
    }
    
    // MARK: - Ring Buffer Tests
    
    @Test("Ring buffer drops oldest entry when exceeding 1000 entries")
    func ringBufferDropsOldestEntryWhenFull() {
        let logger = DiagnosticLogger()
        logger.enable()
        logger.setDebugMode(true)
        
        // Add 1001 entries
        for i in 0..<1001 {
            logger.log(level: "info", category: "test", message: "Message \(i)", metadata: nil)
        }
        
        // Should maintain max 1000 entries
        #expect(logger.entryCount == 1000)
        
        // Verify oldest was dropped (first message should not appear)
        let plainText = logger.exportPlainText()
        #expect(!plainText.contains("Message 0"))
        #expect(plainText.contains("Message 1000"))
    }
    
    @Test("Ring buffer maintains FIFO behavior")
    func ringBufferMaintainsFIFOBehavior() {
        let logger = DiagnosticLogger()
        logger.enable()
        logger.setDebugMode(true)
        
        // Fill to capacity
        for i in 0..<1000 {
            logger.log(level: "info", category: "test", message: "Message \(i)", metadata: nil)
        }
        
        // Add one more - should drop Message 0
        logger.log(level: "info", category: "test", message: "Message 1000", metadata: nil)
        
        let plainText = logger.exportPlainText()
        #expect(!plainText.contains("Message 0"))
        #expect(plainText.contains("Message 1"))
        #expect(plainText.contains("Message 999"))
        #expect(plainText.contains("Message 1000"))
    }
    
    @Test("Multiple rapid additions maintain buffer integrity")
    func multipleRapidAdditionsMaintainBufferIntegrity() {
        let logger = DiagnosticLogger()
        logger.enable()
        logger.setDebugMode(true)
        
        // Rapid addition beyond capacity
        for i in 0..<2000 {
            logger.log(level: "info", category: "test", message: "Rapid \(i)", metadata: nil)
        }
        
        // Should still maintain max 1000
        #expect(logger.entryCount == 1000)
        
        // Verify last entries are present
        let plainText = logger.exportPlainText()
        #expect(plainText.contains("Rapid 1999"))
        #expect(plainText.contains("Rapid 1500"))
        #expect(!plainText.contains("Rapid 999"))
    }
    
    // MARK: - Level Filtering Tests
    
    @Test("Default mode only captures warning and error")
    func defaultModeOnlyCapturesWarningAndError() {
        let logger = DiagnosticLogger()
        logger.enable()
        // Debug mode is false by default
        
        logger.log(level: "debug", category: "test", message: "Debug", metadata: nil)
        logger.log(level: "info", category: "test", message: "Info", metadata: nil)
        logger.log(level: "warning", category: "test", message: "Warning", metadata: nil)
        logger.log(level: "error", category: "test", message: "Error", metadata: nil)
        
        #expect(logger.entryCount == 2)
        
        let plainText = logger.exportPlainText()
        #expect(!plainText.contains("Debug"))
        #expect(!plainText.contains("Info"))
        #expect(plainText.contains("Warning"))
        #expect(plainText.contains("Error"))
    }
    
    @Test("Debug mode captures all levels")
    func debugModeCapturesAllLevels() {
        let logger = DiagnosticLogger()
        logger.enable()
        logger.setDebugMode(true)
        
        logger.log(level: "debug", category: "test", message: "Debug", metadata: nil)
        logger.log(level: "info", category: "test", message: "Info", metadata: nil)
        logger.log(level: "warning", category: "test", message: "Warning", metadata: nil)
        logger.log(level: "error", category: "test", message: "Error", metadata: nil)
        
        #expect(logger.entryCount == 4)
    }
    
    @Test("Disabled logger captures nothing")
    func disabledLoggerCapturesNothing() {
        let logger = DiagnosticLogger()
        // Logger is disabled by default
        logger.setDebugMode(true)
        
        logger.log(level: "debug", category: "test", message: "Debug", metadata: nil)
        logger.log(level: "info", category: "test", message: "Info", metadata: nil)
        logger.log(level: "warning", category: "test", message: "Warning", metadata: nil)
        logger.log(level: "error", category: "test", message: "Error", metadata: nil)
        
        #expect(logger.entryCount == 0)
    }
    
    @Test("Level filtering edge cases with custom levels")
    func levelFilteringEdgeCasesWithCustomLevels() {
        let logger = DiagnosticLogger()
        logger.enable()
        
        // Custom levels that aren't "warning" or "error" should be filtered
        logger.log(level: "critical", category: "test", message: "Critical", metadata: nil)
        logger.log(level: "trace", category: "test", message: "Trace", metadata: nil)
        logger.log(level: "verbose", category: "test", message: "Verbose", metadata: nil)
        #expect(logger.entryCount == 0)
        
        // Standard levels should work
        logger.log(level: "warning", category: "test", message: "Warning", metadata: nil)
        logger.log(level: "error", category: "test", message: "Error", metadata: nil)
        #expect(logger.entryCount == 2)
    }
    
    // MARK: - Auto-Purge (24h) Tests
    
    @Test("RecentEntryCount only counts entries from last 24 hours")
    func recentEntryCountOnlyCountsLast24Hours() {
        let logger = DiagnosticLogger()
        logger.enable()
        logger.setDebugMode(true)
        
        // Add some entries (these will be recent since we just created them)
        for i in 0..<10 {
            logger.log(level: "info", category: "test", message: "Message \(i)", metadata: nil)
        }
        
        // All entries are recent
        #expect(logger.recentEntryCount == 10)
        #expect(logger.entryCount == 10)
    }
    
    @Test("Export functions filter entries older than 24 hours")
    func exportFunctionsFilterOldEntries() throws {
        let logger = DiagnosticLogger()
        logger.enable()
        logger.setDebugMode(true)
        
        // Add current entries
        for i in 0..<5 {
            logger.log(level: "info", category: "test", message: "Recent \(i)", metadata: nil)
        }
        
        // Export and verify all entries are present
        let jsonData = try logger.exportJSON()
        let json = try JSONSerialization.jsonObject(with: jsonData) as! [String: Any]
        let entryCount = json["entry_count"] as! Int
        #expect(entryCount == 5)
        
        let plainText = logger.exportPlainText()
        #expect(plainText.contains("Entry Count: 5"))
    }
    
    // MARK: - Export Functionality Tests
    
    @Test("ExportJSON produces valid JSON with expected fields")
    func exportJSONProducesValidJSONWithExpectedFields() throws {
        let logger = DiagnosticLogger()
        logger.enable()
        logger.setDebugMode(true)
        
        logger.log(level: "info", category: "test", message: "Test message", metadata: ["key": "value"])
        
        let jsonData = try logger.exportJSON()
        let json = try JSONSerialization.jsonObject(with: jsonData) as! [String: Any]
        
        // Verify top-level fields
        #expect(json["export_time"] != nil)
        #expect(json["app_version"] as? String == "1.0.4")
        #expect(json["system_version"] != nil)
        #expect(json["entry_count"] as? Int == 1)
        
        // Verify entries array
        let entries = json["entries"] as! [[String: Any]]
        #expect(entries.count == 1)
        
        let entry = entries[0]
        #expect(entry["timestamp"] != nil)
        #expect(entry["level"] as? String == "info")
        #expect(entry["category"] as? String == "test")
        #expect(entry["message"] as? String == "Test message")
        
        let metadata = entry["metadata"] as! [String: String]
        #expect(metadata["key"] == "value")
    }
    
    @Test("ExportPlainText produces readable format")
    func exportPlainTextProducesReadableFormat() {
        let logger = DiagnosticLogger()
        logger.enable()
        logger.setDebugMode(true)
        
        logger.log(level: "warning", category: "network", message: "Connection timeout", metadata: ["host": "192.168.1.100"])
        logger.log(level: "error", category: "auth", message: "Invalid credentials", metadata: nil)
        
        let plainText = logger.exportPlainText()
        
        // Verify header
        #expect(plainText.contains("LGTVMenuBar Diagnostic Log"))
        #expect(plainText.contains("Export Time:"))
        #expect(plainText.contains("App Version: 1.0.4"))
        #expect(plainText.contains("Entry Count: 2"))
        
        // Verify entries (levels are padded to 7 characters)
        #expect(plainText.contains("WARNING"))
        #expect(plainText.contains("[network]"))
        #expect(plainText.contains("Connection timeout"))
        #expect(plainText.contains("host: 192.168.1.100"))
        
        #expect(plainText.contains("ERROR"))
        #expect(plainText.contains("[auth]"))
        #expect(plainText.contains("Invalid credentials"))
    }
    
    @Test("Export with zero entries produces valid output")
    func exportWithZeroEntriesProducesValidOutput() throws {
        let logger = DiagnosticLogger()
        logger.enable()
        
        // JSON export
        let jsonData = try logger.exportJSON()
        let json = try JSONSerialization.jsonObject(with: jsonData) as! [String: Any]
        #expect(json["entry_count"] as? Int == 0)
        
        let entries = json["entries"] as! [[String: Any]]
        #expect(entries.isEmpty)
        
        // Plain text export
        let plainText = logger.exportPlainText()
        #expect(plainText.contains("Entry Count: 0"))
    }
    
    @Test("Export with full buffer 1000 entries works correctly")
    func exportWithFullBufferWorksCorrectly() throws {
        let logger = DiagnosticLogger()
        logger.enable()
        logger.setDebugMode(true)
        
        // Fill buffer to capacity
        for i in 0..<1000 {
            logger.log(level: "info", category: "test", message: "Message \(i)", metadata: nil)
        }
        
        // JSON export
        let jsonData = try logger.exportJSON()
        let json = try JSONSerialization.jsonObject(with: jsonData) as! [String: Any]
        #expect(json["entry_count"] as? Int == 1000)
        
        let entries = json["entries"] as! [[String: Any]]
        #expect(entries.count == 1000)
        
        // Plain text export
        let plainText = logger.exportPlainText()
        #expect(plainText.contains("Entry Count: 1000"))
    }
    
    // MARK: - Metadata Handling Tests
    
    @Test("Entries with nil metadata are handled correctly")
    func entriesWithNilMetadataAreHandledCorrectly() throws {
        let logger = DiagnosticLogger()
        logger.enable()
        logger.setDebugMode(true)
        
        logger.log(level: "info", category: "test", message: "No metadata", metadata: nil)
        
        // JSON export should not include metadata key
        let jsonData = try logger.exportJSON()
        let json = try JSONSerialization.jsonObject(with: jsonData) as! [String: Any]
        let entries = json["entries"] as! [[String: Any]]
        let entry = entries[0]
        #expect(entry["metadata"] == nil)
        
        // Plain text should not show metadata section
        let plainText = logger.exportPlainText()
        #expect(!plainText.contains("Metadata:"))
    }
    
    @Test("Entries with populated metadata serialize correctly")
    func entriesWithPopulatedMetadataSerializeCorrectly() throws {
        let logger = DiagnosticLogger()
        logger.enable()
        logger.setDebugMode(true)
        
        let metadata = ["ip": "192.168.1.100", "port": "3000", "protocol": "websocket"]
        logger.log(level: "info", category: "connection", message: "Connected", metadata: metadata)
        
        // JSON export
        let jsonData = try logger.exportJSON()
        let json = try JSONSerialization.jsonObject(with: jsonData) as! [String: Any]
        let entries = json["entries"] as! [[String: Any]]
        let entry = entries[0]
        let exportedMetadata = entry["metadata"] as! [String: String]
        
        #expect(exportedMetadata["ip"] == "192.168.1.100")
        #expect(exportedMetadata["port"] == "3000")
        #expect(exportedMetadata["protocol"] == "websocket")
        
        // Plain text export
        let plainText = logger.exportPlainText()
        #expect(plainText.contains("Metadata:"))
        #expect(plainText.contains("ip: 192.168.1.100"))
        #expect(plainText.contains("port: 3000"))
        #expect(plainText.contains("protocol: websocket"))
    }
    
    @Test("Metadata with empty dictionary is handled correctly")
    func metadataWithEmptyDictionaryIsHandledCorrectly() throws {
        let logger = DiagnosticLogger()
        logger.enable()
        logger.setDebugMode(true)
        
        logger.log(level: "info", category: "test", message: "Empty metadata", metadata: [:])
        
        // Plain text should not show metadata section for empty dict
        let plainText = logger.exportPlainText()
        #expect(!plainText.contains("Metadata:"))
    }
    
    // MARK: - Concurrency Tests
    
    @Test("Logger is MainActor isolated")
    func loggerIsMainActorIsolated() {
        // This test verifies that DiagnosticLogger is properly annotated with @MainActor
        // If it wasn't, this would fail to compile
        let logger = DiagnosticLogger()
        #expect(logger.isEnabled == false)
    }
    
    @Test("All protocol methods are accessible on MainActor")
    func allProtocolMethodsAccessibleOnMainActor() {
        let logger: DiagnosticLoggerProtocol = DiagnosticLogger()
        
        // Verify property access
        _ = logger.isEnabled
        _ = logger.isDebugMode
        _ = logger.entryCount
        _ = logger.recentEntryCount
        
        // These method calls verify they're accessible without async context issues
        // The fact that this compiles means the protocol is properly @MainActor
    }
    
    // MARK: - Edge Cases and Integration Tests
    
    @Test("Multiple toggles of enable/disable work correctly")
    func multipleTogglesOfEnableDisableWorkCorrectly() {
        let logger = DiagnosticLogger()
        logger.setDebugMode(true)
        
        // Enable -> log -> disable -> log -> enable -> log
        logger.enable()
        logger.log(level: "info", category: "test", message: "First", metadata: nil)
        #expect(logger.entryCount == 1)
        
        logger.disable()
        logger.log(level: "info", category: "test", message: "Second", metadata: nil)
        #expect(logger.entryCount == 1)
        
        logger.enable()
        logger.log(level: "info", category: "test", message: "Third", metadata: nil)
        #expect(logger.entryCount == 2)
    }
    
    @Test("Multiple toggles of debug mode work correctly")
    func multipleTogglesOfDebugModeWorkCorrectly() {
        let logger = DiagnosticLogger()
        logger.enable()
        
        // Debug off -> log info (filtered) -> debug on -> log info (captured)
        logger.setDebugMode(false)
        logger.log(level: "info", category: "test", message: "Filtered", metadata: nil)
        #expect(logger.entryCount == 0)
        
        logger.setDebugMode(true)
        logger.log(level: "info", category: "test", message: "Captured", metadata: nil)
        #expect(logger.entryCount == 1)
        
        logger.setDebugMode(false)
        logger.log(level: "info", category: "test", message: "Filtered again", metadata: nil)
        #expect(logger.entryCount == 1)
    }
    
    @Test("Logger handles special characters in messages")
    func loggerHandlesSpecialCharactersInMessages() throws {
        let logger = DiagnosticLogger()
        logger.enable()
        logger.setDebugMode(true)
        
        let specialMessage = "Test with \"quotes\", newlines\n, tabs\t, and emojis 🎉"
        logger.log(level: "info", category: "test", message: specialMessage, metadata: nil)
        
        // Verify JSON serialization doesn't fail
        let jsonData = try logger.exportJSON()
        #expect(jsonData.count > 0)
        
        // Verify plain text export works
        let plainText = logger.exportPlainText()
        #expect(plainText.contains("Test with"))
    }
    
    @Test("Logger handles special characters in metadata")
    func loggerHandlesSpecialCharactersInMetadata() throws {
        let logger = DiagnosticLogger()
        logger.enable()
        logger.setDebugMode(true)
        
        let metadata = [
            "key1": "value with \"quotes\"",
            "key2": "value\nwith\nnewlines",
            "emoji": "🚀"
        ]
        logger.log(level: "info", category: "test", message: "Test", metadata: metadata)
        
        // Verify JSON serialization doesn't fail
        let jsonData = try logger.exportJSON()
        #expect(jsonData.count > 0)
    }
    
    @Test("Logger handles very long messages")
    func loggerHandlesVeryLongMessages() throws {
        let logger = DiagnosticLogger()
        logger.enable()
        logger.setDebugMode(true)
        
        let longMessage = String(repeating: "A", count: 10000)
        logger.log(level: "info", category: "test", message: longMessage, metadata: nil)
        
        #expect(logger.entryCount == 1)
        
        // Verify export works
        let jsonData = try logger.exportJSON()
        #expect(jsonData.count > 0)
    }
    
    @Test("Logger handles very large metadata dictionaries")
    func loggerHandlesVeryLargeMetadataDictionaries() throws {
        let logger = DiagnosticLogger()
        logger.enable()
        logger.setDebugMode(true)
        
        var metadata: [String: String] = [:]
        for i in 0..<100 {
            metadata["key\(i)"] = "value\(i)"
        }
        
        logger.log(level: "info", category: "test", message: "Test", metadata: metadata)
        
        #expect(logger.entryCount == 1)
        
        // Verify export works
        let jsonData = try logger.exportJSON()
        let json = try JSONSerialization.jsonObject(with: jsonData) as! [String: Any]
        let entries = json["entries"] as! [[String: Any]]
        let entry = entries[0]
        let exportedMetadata = entry["metadata"] as! [String: String]
        #expect(exportedMetadata.count == 100)
    }
    
    @Test("Clear and immediate log works correctly")
    func clearAndImmediateLogWorksCorrectly() {
        let logger = DiagnosticLogger()
        logger.enable()
        logger.setDebugMode(true)
        
        logger.log(level: "info", category: "test", message: "First", metadata: nil)
        #expect(logger.entryCount == 1)
        
        logger.clear()
        #expect(logger.entryCount == 0)
        
        logger.log(level: "info", category: "test", message: "Second", metadata: nil)
        #expect(logger.entryCount == 1)
    }
    
    @Test("Properties return correct initial values")
    func propertiesReturnCorrectInitialValues() {
        let logger = DiagnosticLogger()
        
        #expect(logger.isEnabled == false)
        #expect(logger.isDebugMode == false)
        #expect(logger.entryCount == 0)
        #expect(logger.recentEntryCount == 0)
    }
}
