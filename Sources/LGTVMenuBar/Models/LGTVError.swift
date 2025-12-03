import Foundation

/// Errors that can occur when communicating with LG WebOS TVs
public enum LGTVError: Error, Equatable, Sendable {
    case connectionFailed(String)
    case pairingRejected
    case pairingTimeout
    case commandFailed(String)
    case invalidResponse
    case tvNotFound
    case networkError(Error)
    case wakeFailed
    case wolError(Error)
    case keychainError(Error)
    case webosError(String)
    case launchAtLoginError(String)
    case mediaKeyError(String)
    case powerManagementError(String)
    
    // MARK: - Equatable
    
    public static func == (lhs: LGTVError, rhs: LGTVError) -> Bool {
        switch (lhs, rhs) {
        case (.connectionFailed(let a), .connectionFailed(let b)): return a == b
        case (.pairingRejected, .pairingRejected): return true
        case (.pairingTimeout, .pairingTimeout): return true
        case (.commandFailed(let a), .commandFailed(let b)): return a == b
        case (.invalidResponse, .invalidResponse): return true
        case (.tvNotFound, .tvNotFound): return true
        case (.networkError, .networkError): return true  // Compare by case only
        case (.wakeFailed, .wakeFailed): return true
        case (.wolError, .wolError): return true  // Compare by case only
        case (.keychainError, .keychainError): return true  // Compare by case only
        case (.webosError(let a), .webosError(let b)): return a == b
        case (.launchAtLoginError(let a), .launchAtLoginError(let b)): return a == b
        case (.mediaKeyError(let a), .mediaKeyError(let b)): return a == b
        case (.powerManagementError(let a), .powerManagementError(let b)): return a == b
        default: return false
        }
    }
}

// MARK: - LocalizedError

extension LGTVError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .connectionFailed(let message):
            return "Connection failed: \(message)"
        case .pairingRejected:
            return "Pairing was rejected by the TV"
        case .pairingTimeout:
            return "Pairing timed out - no response from TV"
        case .commandFailed(let message):
            return "Command failed: \(message)"
        case .invalidResponse:
            return "Received an invalid response from the TV"
        case .tvNotFound:
            return "TV not found on the network"
        case .networkError(let underlyingError):
            return "Network error: \(underlyingError.localizedDescription)"
        case .wakeFailed:
            return "Failed to wake the TV"
        case .wolError(let underlyingError):
            return "Wake-on-LAN error: \(underlyingError.localizedDescription)"
        case .keychainError(let underlyingError):
            return "Keychain error: \(underlyingError.localizedDescription)"
        case .webosError(let message):
            return "WebOS error: \(message)"
        case .launchAtLoginError(let message):
            return "Launch at login error: \(message)"
        case .mediaKeyError(let message):
            return "Media key error: \(message)"
        case .powerManagementError(let message):
            return "Power management error: \(message)"
        }
    }
}
