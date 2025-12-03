import Foundation
import ServiceManagement

/// Protocol abstracting login item management for testability
public protocol LoginItemServiceProtocol: Sendable {
    /// Whether the app is currently set to launch at login
    var isEnabled: Bool { get }
    
    /// Register the app to launch at login
    func register() throws
    
    /// Unregister the app from launching at login
    func unregister() throws
}

/// Errors that can occur during login item operations
public enum LoginItemError: Error, LocalizedError {
    case registrationFailed(Error)
    case unregistrationFailed(Error)
    
    public var errorDescription: String? {
        switch self {
        case .registrationFailed(let error):
            return "Failed to register login item: \(error.localizedDescription)"
        case .unregistrationFailed(let error):
            return "Failed to unregister login item: \(error.localizedDescription)"
        }
    }
}

/// Default implementation using SMAppService
@available(macOS 13.0, *)
public struct SystemLoginItemService: LoginItemServiceProtocol {
    public init() {}
    
    public var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }
    
    public func register() throws {
        do {
            try SMAppService.mainApp.register()
        } catch {
            throw LoginItemError.registrationFailed(error)
        }
    }
    
    public func unregister() throws {
        do {
            try SMAppService.mainApp.unregister()
        } catch {
            throw LoginItemError.unregistrationFailed(error)
        }
    }
}
