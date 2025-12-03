import Foundation
import Security
import OSLog

/// Production implementation of KeychainManagerProtocol using Security framework
/// 
/// This service provides secure storage for TV client keys using the iOS/macOS keychain.
/// TV configuration (non-sensitive) is stored in UserDefaults instead.
/// 
/// Keychain items are stored with the following attributes:
/// - Service: "com.lgtvmenubar.clientkeys"
/// - Account: TV IP address (unique identifier)
/// - Accessibility: .whenUnlocked (user must be authenticated)
/// - Data type: Generic password with client key string
/// 
/// Note: The Security framework operations are thread-safe, so this class is safe to use
/// from multiple concurrent contexts without requiring actor isolation.
public final class KeychainManager: KeychainManagerProtocol, Sendable {
    
    // MARK: - Constants
    
    /// Keychain service identifier for client keys
    private static let clientKeyService = "com.lgtvmenubar.clientkeys"
    
    // MARK: - Initialization
    
    /// Initialize a new KeychainManager instance
    public init() {}
    
    // MARK: - Client Key Storage
    
    /// Save a client key for a specific TV IP address
    /// - Parameters:
    ///   - clientKey: The client key string received from the TV during pairing
    ///   - ipAddress: The IP address of the TV (used as identifier)
    /// - Throws: LGTVError.keychainError if save operation fails
    public func saveClientKey(_ clientKey: String, for ipAddress: String) throws {
        do {
            try save(clientKey, service: Self.clientKeyService, forKey: ipAddress)
        } catch let error as LGTVError {
            throw error
        } catch {
            throw LGTVError.keychainError(error)
        }
    }
    
    /// Load a client key for a specific TV IP address
    /// - Parameter ipAddress: The IP address of the TV
    /// - Returns: The stored client key, or nil if not found
    /// - Throws: LGTVError.keychainError if load operation fails
    public func loadClientKey(for ipAddress: String) throws -> String? {
        do {
            return try retrieve(service: Self.clientKeyService, forKey: ipAddress)
        } catch let error as LGTVError {
            throw error
        } catch {
            throw LGTVError.keychainError(error)
        }
    }
    
    /// Delete a client key for a specific TV IP address
    /// - Parameter ipAddress: The IP address of the TV
    /// - Throws: LGTVError.keychainError if delete operation fails
    public func deleteClientKey(for ipAddress: String) throws {
        do {
            try delete(service: Self.clientKeyService, forKey: ipAddress)
        } catch let error as LGTVError {
            throw error
        } catch {
            throw LGTVError.keychainError(error)
        }
    }
    
    // MARK: - Private Keychain Operations
    
    /// Save a string value to the keychain
    /// 
    /// This is a low-level method that handles the actual keychain storage operations.
    /// It creates or updates a generic password item in the keychain.
    /// 
    /// - Parameters:
    ///   - value: The string value to save
    ///   - service: The keychain service identifier
    ///   - key: The key to save the value under
    /// - Throws: KeychainError if the save operation fails
    private func save(_ value: String, service: String, forKey key: String) throws {
        guard let valueData = value.data(using: .utf8) else {
            throw KeychainError.dataConversionFailed
        }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: valueData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]
        
        // First, try to delete any existing item
        try delete(service: service, forKey: key)
        
        // Add the new item
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else {
            throw KeychainError.saveFailed(status)
        }
    }
    
    /// Retrieve a string value from the keychain
    /// 
    /// This is a low-level method that handles the actual keychain retrieval operations.
    /// It searches for a generic password item and returns its data as a string.
    /// 
    /// - Parameters:
    ///   - service: The keychain service identifier
    ///   - key: The key to retrieve the value for
    /// - Returns: The stored value, or nil if not found
    /// - Throws: KeychainError if the retrieve operation fails
    private func retrieve(service: String, forKey key: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let value = String(data: data, encoding: .utf8) else {
                throw KeychainError.dataConversionFailed
            }
            return value
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.retrieveFailed(status)
        }
    }
    
    /// Delete a value from the keychain
    /// 
    /// This is a low-level method that handles the actual keychain deletion operations.
    /// It searches for and removes a generic password item.
    /// 
    /// - Parameters:
    ///   - service: The keychain service identifier
    ///   - key: The key to delete
    /// - Throws: KeychainError if the delete operation fails
    private func delete(service: String, forKey key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }
}