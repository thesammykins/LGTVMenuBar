import Foundation
import Network

/// Protocol abstracting UDP operations for testability
public protocol UDPClientProtocol: Sendable {
    /// Send data to a UDP endpoint
    /// - Parameters:
    ///   - data: The data to send
    ///   - host: The target host
    ///   - port: The target port
    func send(_ data: Data, to host: String, port: UInt16) async throws
}

/// Errors that can occur during UDP operations
public enum UDPError: Error, LocalizedError {
    case sendFailed(String)
    case connectionFailed(String)
    case invalidAddress
    
    public var errorDescription: String? {
        switch self {
        case .sendFailed(let reason):
            return "Failed to send UDP packet: \(reason)"
        case .connectionFailed(let reason):
            return "Failed to establish UDP connection: \(reason)"
        case .invalidAddress:
            return "Invalid network address"
        }
    }
}
