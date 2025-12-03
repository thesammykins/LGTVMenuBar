import Foundation
@testable import LGTVMenuBar

/// Mock implementation of KeychainManagerProtocol for testing
final class MockKeychainManager: KeychainManagerProtocol, @unchecked Sendable {
    
    // MARK: - Configuration
    
    /// Whether save operations should throw an error
    var shouldThrowOnSave = false
    
    /// Whether load operations should throw an error
    var shouldThrowOnLoad = false
    
    /// Whether delete operations should throw an error
    var shouldThrowOnDelete = false
    
    /// Whether hasConfiguration operations should throw an error
    var shouldThrowOnHasConfiguration = false
    
    /// Whether saveClientKey operations should throw an error
    var shouldThrowOnSaveClientKey = false
    
    /// Whether loadClientKey operations should throw an error
    var shouldThrowOnLoadClientKey = false
    
    /// Whether deleteClientKey operations should throw an error
    var shouldThrowOnDeleteClientKey = false
    
    /// Error to throw when configured to throw
    var errorToThrow: Error = LGTVError.keychainError(KeychainError.saveFailed(-1))
    
    // MARK: - Call History
    
    /// History of saveConfiguration calls
    private(set) var saveConfigurationCalls: [TVConfiguration] = []
    
    /// History of loadConfiguration calls
    private(set) var loadConfigurationCalls: Int = 0
    
    /// History of deleteConfiguration calls
    private(set) var deleteConfigurationCalls: Int = 0
    
    /// History of hasConfiguration calls
    private(set) var hasConfigurationCalls: Int = 0
    
    /// History of saveClientKey calls (ipAddress, clientKey)
    private(set) var saveClientKeyCalls: [(ipAddress: String, clientKey: String)] = []
    
    /// History of loadClientKey calls
    private(set) var loadClientKeyCalls: [String] = []
    
    /// History of deleteClientKey calls
    private(set) var deleteClientKeyCalls: [String] = []
    
    // MARK: - Mock Storage
    
    /// In-memory storage for mock TV configuration
    private var storedConfiguration: TVConfiguration?
    
    /// In-memory storage for mock client keys (keyed by IP address)
    private var storedClientKeys: [String: String] = [:]
    
    // MARK: - KeychainManagerProtocol Implementation
    
    func saveConfiguration(_ configuration: TVConfiguration) throws {
        saveConfigurationCalls.append(configuration)
        
        if shouldThrowOnSave {
            throw errorToThrow
        }
        
        storedConfiguration = configuration
    }
    
    func loadConfiguration() throws -> TVConfiguration? {
        loadConfigurationCalls += 1
        
        if shouldThrowOnLoad {
            throw errorToThrow
        }
        
        return storedConfiguration
    }
    
    func deleteConfiguration() throws {
        deleteConfigurationCalls += 1
        
        if shouldThrowOnDelete {
            throw errorToThrow
        }
        
        storedConfiguration = nil
    }
    
    func hasConfiguration() throws -> Bool {
        hasConfigurationCalls += 1
        
        if shouldThrowOnHasConfiguration {
            throw errorToThrow
        }
        
        return storedConfiguration != nil
    }
    
    func saveClientKey(_ clientKey: String, for ipAddress: String) throws {
        saveClientKeyCalls.append((ipAddress, clientKey))
        
        if shouldThrowOnSaveClientKey {
            throw errorToThrow
        }
        
        storedClientKeys[ipAddress] = clientKey
    }
    
    func loadClientKey(for ipAddress: String) throws -> String? {
        loadClientKeyCalls.append(ipAddress)
        
        if shouldThrowOnLoadClientKey {
            throw errorToThrow
        }
        
        return storedClientKeys[ipAddress]
    }
    
    func deleteClientKey(for ipAddress: String) throws {
        deleteClientKeyCalls.append(ipAddress)
        
        if shouldThrowOnDeleteClientKey {
            throw errorToThrow
        }
        
        storedClientKeys.removeValue(forKey: ipAddress)
    }
    
    // MARK: - Test Helpers
    
    /// Reset all mock state
    func reset() {
        saveConfigurationCalls.removeAll()
        loadConfigurationCalls = 0
        deleteConfigurationCalls = 0
        hasConfigurationCalls = 0
        saveClientKeyCalls.removeAll()
        loadClientKeyCalls.removeAll()
        deleteClientKeyCalls.removeAll()
        storedConfiguration = nil
        storedClientKeys.removeAll()
        
        shouldThrowOnSave = false
        shouldThrowOnLoad = false
        shouldThrowOnDelete = false
        shouldThrowOnHasConfiguration = false
        shouldThrowOnSaveClientKey = false
        shouldThrowOnLoadClientKey = false
        shouldThrowOnDeleteClientKey = false
        errorToThrow = LGTVError.keychainError(KeychainError.saveFailed(-1))
    }
    
    /// Pre-populate storage with test configuration
    func setStoredConfiguration(_ configuration: TVConfiguration) {
        storedConfiguration = configuration
    }
    
    /// Pre-populate storage with test client key
    func setStoredClientKey(_ clientKey: String, for ipAddress: String) {
        storedClientKeys[ipAddress] = clientKey
    }
    
    /// Get the number of times saveConfiguration was called
    func saveConfigurationCallCount() -> Int {
        return saveConfigurationCalls.count
    }
    
    /// Get the number of times loadConfiguration was called
    func loadConfigurationCallCount() -> Int {
        return loadConfigurationCalls
    }
    
    /// Get the number of times deleteConfiguration was called
    func deleteConfigurationCallCount() -> Int {
        return deleteConfigurationCalls
    }
    
    /// Get the number of times hasConfiguration was called
    func hasConfigurationCallCount() -> Int {
        return hasConfigurationCalls
    }
    
    /// Get the last saved configuration
    func getLastSavedConfiguration() -> TVConfiguration? {
        return saveConfigurationCalls.last
    }
    
    /// Get the number of times saveClientKey was called
    func saveClientKeyCallCount() -> Int {
        return saveClientKeyCalls.count
    }
    
    /// Get the number of times loadClientKey was called
    func loadClientKeyCallCount() -> Int {
        return loadClientKeyCalls.count
    }
    
    /// Get the number of times deleteClientKey was called
    func deleteClientKeyCallCount() -> Int {
        return deleteClientKeyCalls.count
    }
    
    /// Get the last saved client key
    func getLastSavedClientKey() -> (ipAddress: String, clientKey: String)? {
        return saveClientKeyCalls.last
    }
}