import Foundation

/// Protocol abstracting WebSocket operations for testability
public protocol WebSocketClientProtocol: Sendable {
    /// Connect to a WebSocket server
    func connect(to url: URL) async throws
    
    /// Disconnect from the WebSocket server
    func disconnect() async
    
    /// Send a message to the WebSocket server
    func send(_ message: Data) async throws
    
    /// Receive a message from the WebSocket server
    func receive() async throws -> Data
    
    /// Whether the connection is currently active
    var isConnected: Bool { get }
}
