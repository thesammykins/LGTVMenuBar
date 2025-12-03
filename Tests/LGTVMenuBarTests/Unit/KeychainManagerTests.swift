import Testing
import Foundation
@testable import LGTVMenuBar

/// Test suite for KeychainManager
/// 
/// Note: These tests use the real keychain, so they may require keychain access
/// in the test environment. Tests that depend on keychain operations may be skipped
/// if the keychain is not accessible due to permissions.
@Suite("KeychainManager Tests")
struct KeychainManagerTests {
    
    /// Helper to check if keychain is accessible
    private static func isKeychainAccessible() -> Bool {
        let manager = KeychainManager()
        do {
            // Try a basic operation
            _ = try manager.hasConfiguration()
            return true
        } catch {
            return false
        }
    }
    
    // MARK: - Configuration Tests
    
    @Test("Save and load configuration preserves all properties")
    func saveAndLoadConfiguration() throws {
        let keychainManager = KeychainManager()
        
        // Skip if keychain not accessible
        guard Self.isKeychainAccessible() else {
            return // Skip test gracefully
        }
        
        // Clean up any existing test data
        try? keychainManager.deleteConfiguration()
        
        defer {
            try? keychainManager.deleteConfiguration()
        }
        
        let configuration = TVConfiguration(
            name: "Test TV",
            ipAddress: "192.168.1.100",
            macAddress: "AA:BB:CC:DD:EE:FF"
        )
        
        try keychainManager.saveConfiguration(configuration)
        let loadedConfiguration = try keychainManager.loadConfiguration()
        
        #expect(loadedConfiguration != nil)
        #expect(loadedConfiguration?.name == configuration.name)
        #expect(loadedConfiguration?.ipAddress == configuration.ipAddress)
        #expect(loadedConfiguration?.macAddress == configuration.macAddress)
    }
    
    @Test("hasConfiguration returns false when no configuration exists")
    func hasConfigurationReturnsFalseWhenEmpty() throws {
        let keychainManager = KeychainManager()
        
        // Skip if keychain not accessible
        guard Self.isKeychainAccessible() else {
            return
        }
        
        // Clean up any existing test data
        try? keychainManager.deleteConfiguration()
        
        let hasConfig = try keychainManager.hasConfiguration()
        
        #expect(hasConfig == false)
    }
    
    @Test("hasConfiguration returns true after saving configuration")
    func hasConfigurationReturnsTrueAfterSave() throws {
        let keychainManager = KeychainManager()
        
        // Skip if keychain not accessible
        guard Self.isKeychainAccessible() else {
            return
        }
        
        // Clean up any existing test data
        try? keychainManager.deleteConfiguration()
        
        defer {
            try? keychainManager.deleteConfiguration()
        }
        
        let configuration = TVConfiguration(
            name: "Test TV",
            ipAddress: "192.168.1.100",
            macAddress: "AA:BB:CC:DD:EE:FF"
        )
        try keychainManager.saveConfiguration(configuration)
        
        let hasConfig = try keychainManager.hasConfiguration()
        
        #expect(hasConfig == true)
    }
    
    @Test("loadConfiguration returns nil when no configuration exists")
    func loadNonExistentConfigurationReturnsNil() throws {
        let keychainManager = KeychainManager()
        
        // Skip if keychain not accessible
        guard Self.isKeychainAccessible() else {
            return
        }
        
        // Clean up any existing test data
        try? keychainManager.deleteConfiguration()
        
        let configuration = try keychainManager.loadConfiguration()
        
        #expect(configuration == nil)
    }
    
    // MARK: - Client Key Tests
    
    @Test("Save and load client key for IP address")
    func saveAndLoadClientKey() throws {
        let keychainManager = KeychainManager()
        let testIP = "192.168.1.100"
        let testKey = "test-client-key-12345"
        
        // Skip if keychain not accessible
        guard Self.isKeychainAccessible() else {
            return
        }
        
        // Clean up any existing test data
        try? keychainManager.deleteClientKey(for: testIP)
        
        defer {
            try? keychainManager.deleteClientKey(for: testIP)
        }
        
        try keychainManager.saveClientKey(testKey, for: testIP)
        let loadedKey = try keychainManager.loadClientKey(for: testIP)
        
        #expect(loadedKey == testKey)
    }
    
    @Test("loadClientKey returns nil for non-existent IP")
    func loadClientKeyReturnsNilForUnknownIP() throws {
        let keychainManager = KeychainManager()
        let unknownIP = "10.0.0.1"
        
        // Skip if keychain not accessible
        guard Self.isKeychainAccessible() else {
            return
        }
        
        // Ensure nothing exists
        try? keychainManager.deleteClientKey(for: unknownIP)
        
        let loadedKey = try keychainManager.loadClientKey(for: unknownIP)
        
        #expect(loadedKey == nil)
    }
    
    // MARK: - KeychainError Tests (these don't require real keychain access)
    
    @Test("KeychainError.saveFailed provides localized description")
    func keychainErrorSaveFailedDescription() {
        let error = KeychainError.saveFailed(-25300)
        #expect(error.errorDescription?.contains("Failed to save to keychain") == true)
        #expect(error.errorDescription?.contains("-25300") == true)
    }
    
    @Test("KeychainError.retrieveFailed provides localized description")
    func keychainErrorRetrieveFailedDescription() {
        let error = KeychainError.retrieveFailed(-25300)
        #expect(error.errorDescription?.contains("Failed to retrieve from keychain") == true)
    }
    
    @Test("KeychainError.deleteFailed provides localized description")
    func keychainErrorDeleteFailedDescription() {
        let error = KeychainError.deleteFailed(-25300)
        #expect(error.errorDescription?.contains("Failed to delete from keychain") == true)
    }
    
    @Test("KeychainError.dataConversionFailed provides localized description")
    func keychainErrorDataConversionFailedDescription() {
        let error = KeychainError.dataConversionFailed
        #expect(error.errorDescription?.contains("Failed to convert data") == true)
    }
    
    @Test("KeychainError conforms to Error protocol")
    func keychainErrorConformsToError() {
        let error: Error = KeychainError.saveFailed(-25300)
        #expect(error is KeychainError)
    }
    
    @Test("KeychainError conforms to LocalizedError protocol")
    func keychainErrorConformsToLocalizedError() {
        let error: LocalizedError = KeychainError.saveFailed(-25300)
        #expect(error.errorDescription != nil)
    }
}
