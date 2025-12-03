import Foundation

/// Protocol for managing persisted client keys in the keychain
public protocol KeychainManagerProtocol: Sendable {
    func saveClientKey(_ clientKey: String, for ipAddress: String) throws
    func loadClientKey(for ipAddress: String) throws -> String?
    func deleteClientKey(for ipAddress: String) throws
}
