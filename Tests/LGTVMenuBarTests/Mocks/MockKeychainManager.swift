import Foundation
@testable import LGTVMenuBar

/// Mock implementation of KeychainManagerProtocol for testing
/// Only handles client key operations (configuration is now in UserDefaults)
final class MockKeychainManager: KeychainManagerProtocol, @unchecked Sendable {
    
    // MARK: - Configuration
    
    /// Whether saveClientKey operations should throw an error
    var shouldThrowOnSaveClientKey = false
    
    /// Whether loadClientKey operations should throw an error
    var shouldThrowOnLoadClientKey = false
    
    /// Whether deleteClientKey operations should throw an error
    var shouldThrowOnDeleteClientKey = false
    
    /// Error to throw when configured to throw
    var errorToThrow: Error = LGTVError.keychainError(KeychainError.saveFailed(-1))
    
    // MARK: - Call History
    
    /// History of saveClientKey calls (ipAddress, clientKey)
    private(set) var saveClientKeyCalls: [(ipAddress: String, clientKey: String)] = []
    
    /// History of loadClientKey calls
    private(set) var loadClientKeyCalls: [String] = []
    
    /// History of deleteClientKey calls
    private(set) var deleteClientKeyCalls: [String] = []
    
    // MARK: - Mock Storage
    
    /// In-memory storage for mock client keys (keyed by IP address)
    private var storedClientKeys: [String: String] = [:]
    
    // MARK: - KeychainManagerProtocol Implementation
    
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
        saveClientKeyCalls.removeAll()
        loadClientKeyCalls.removeAll()
        deleteClientKeyCalls.removeAll()
        storedClientKeys.removeAll()
        
        shouldThrowOnSaveClientKey = false
        shouldThrowOnLoadClientKey = false
        shouldThrowOnDeleteClientKey = false
        errorToThrow = LGTVError.keychainError(KeychainError.saveFailed(-1))
    }
    
    /// Pre-populate storage with test client key
    func setStoredClientKey(_ clientKey: String, for ipAddress: String) {
        storedClientKeys[ipAddress] = clientKey
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