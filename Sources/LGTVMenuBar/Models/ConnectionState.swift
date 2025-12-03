import Foundation

/// Represents the connection state of the WebOS client
public enum ConnectionState: Sendable {
    case disconnected
    case connecting
    case registering
    case connected
    case error(Error)
    
    /// Whether the client is fully connected and ready for commands
    public var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
    
    /// Whether the client is disconnected (not in any connection state)
    public var isDisconnected: Bool {
        if case .disconnected = self { return true }
        return false
    }
    
    /// Whether the client is in a transitional state (connecting or registering)
    public var isTransitioning: Bool {
        switch self {
        case .connecting, .registering: return true
        default: return false
        }
    }
    
    /// Whether the state represents an error condition
    public var hasError: Bool {
        if case .error = self { return true }
        return false
    }
}

// MARK: - Equatable

extension ConnectionState: Equatable {
    public static func == (lhs: ConnectionState, rhs: ConnectionState) -> Bool {
        switch (lhs, rhs) {
        case (.disconnected, .disconnected): return true
        case (.connecting, .connecting): return true
        case (.registering, .registering): return true
        case (.connected, .connected): return true
        case (.error, .error): return true  // Note: errors compare by case only
        default: return false
        }
    }
}

// MARK: - CustomStringConvertible

extension ConnectionState: CustomStringConvertible {
    public var description: String {
        switch self {
        case .connected:
            return "Connected"
        case .disconnected:
            return "Disconnected"
        case .connecting:
            return "Connecting"
        case .registering:
            return "Registering"
        case .error(let error):
            return "Error: \(error.localizedDescription)"
        }
    }
}
