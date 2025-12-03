import Foundation

/// Protocol abstracting Keychain operations for testability
public protocol KeychainServiceProtocol: Sendable {
    /// Save a value to the keychain
    /// - Parameters:
    ///   - value: The string value to save
    ///   - key: The key to save the value under
    func save(_ value: String, forKey key: String) throws
    
    /// Retrieve a value from the keychain
    /// - Parameter key: The key to retrieve the value for
    /// - Returns: The stored value, or nil if not found
    func retrieve(forKey key: String) throws -> String?
    
    /// Delete a value from the keychain
    /// - Parameter key: The key to delete
    func delete(forKey key: String) throws
}

/// Errors that can occur during keychain operations
public enum KeychainError: Error, LocalizedError {
    case saveFailed(OSStatus)
    case retrieveFailed(OSStatus)
    case deleteFailed(OSStatus)
    case dataConversionFailed
    
    public var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            return "Failed to save to keychain: \(status)"
        case .retrieveFailed(let status):
            return "Failed to retrieve from keychain: \(status)"
        case .deleteFailed(let status):
            return "Failed to delete from keychain: \(status)"
        case .dataConversionFailed:
            return "Failed to convert data to/from string"
        }
    }
}
