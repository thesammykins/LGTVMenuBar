import Foundation

/// Protocol for managing persisted TV configuration state and client keys
public protocol KeychainManagerProtocol: Sendable {
    func saveConfiguration(_ configuration: TVConfiguration) throws
    func loadConfiguration() throws -> TVConfiguration?
    func deleteConfiguration() throws
    func hasConfiguration() throws -> Bool
    
    func saveClientKey(_ clientKey: String, for ipAddress: String) throws
    func loadClientKey(for ipAddress: String) throws -> String?
    func deleteClientKey(for ipAddress: String) throws
}
