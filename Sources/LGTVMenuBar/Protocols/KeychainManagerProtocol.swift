import Foundation

/// Protocol for managing persisted client keys in the keychain
public protocol KeychainManagerProtocol: Sendable {
    func saveClientKey(_ clientKey: String, for ipAddress: String) throws
    func loadClientKey(for ipAddress: String) throws -> String?
    func deleteClientKey(for ipAddress: String) throws

    /// Generic secrets (SSH private key, shell password), keyed by an app-defined account name.
    func saveSecret(_ secret: Data, account: String) throws
    func loadSecret(account: String) throws -> Data?
    func deleteSecret(account: String) throws
}
