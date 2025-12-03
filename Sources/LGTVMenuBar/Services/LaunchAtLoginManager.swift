import Foundation
import ServiceManagement
import OSLog

/// Service responsible for managing launch-at-login functionality using SMAppService
@MainActor
final class LaunchAtLoginManager: LaunchAtLoginManagerProtocol {
    private let logger = Logger(subsystem: "com.lgtvmenubar", category: "LaunchAtLoginManager")
    
    /// Bundle identifier for the main app
    private let bundleIdentifier: String
    
    /// Initialize with a custom bundle identifier
    /// - Parameter bundleIdentifier: Bundle identifier to use for SMAppService
    init(bundleIdentifier: String = "com.thesammykins.lgtvmenubar") {
        self.bundleIdentifier = bundleIdentifier
    }
    
    /// Enable launch at login
    /// - Throws: `LGTVError.launchAtLoginError` if enabling fails
    func enableLaunchAtLogin() async throws {
        logger.info("Enabling launch at login for \(self.bundleIdentifier)")
        
        do {
            let service = SMAppService.mainApp
            try service.register()
            
            if service.status == .enabled {
                logger.info("Launch at login enabled successfully")
            } else {
                throw LGTVError.launchAtLoginError("Failed to enable launch at login - service status: \(service.status.rawValue)")
            }
        } catch {
            logger.error("Failed to enable launch at login: \(error.localizedDescription)")
            throw LGTVError.launchAtLoginError("Failed to enable launch at login: \(error.localizedDescription)")
        }
    }
    
    /// Disable launch at login
    /// - Throws: `LGTVError.launchAtLoginError` if disabling fails
    func disableLaunchAtLogin() async throws {
        logger.info("Disabling launch at login for \(self.bundleIdentifier)")
        
        do {
            let service = SMAppService.mainApp
            try await service.unregister()
            
            if service.status == .notFound {
                logger.info("Launch at login disabled successfully")
            } else {
                throw LGTVError.launchAtLoginError("Failed to disable launch at login - service status: \(service.status.rawValue)")
            }
        } catch {
            logger.error("Failed to disable launch at login: \(error.localizedDescription)")
            throw LGTVError.launchAtLoginError("Failed to disable launch at login: \(error.localizedDescription)")
        }
    }
    
    /// Check if launch at login is currently enabled
    /// - Returns: `true` if launch at login is enabled, `false` otherwise
    /// - Throws: `LGTVError.launchAtLoginError` if checking status fails
    func isLaunchAtLoginEnabled() async throws -> Bool {
        do {
            let service = SMAppService.mainApp
            let status = service.status
            
            logger.debug("Launch at login status: \(status.rawValue)")
            
            switch status {
            case .enabled:
                return true
            case .notFound, .notRegistered:
                return false
            case .requiresApproval:
                logger.warning("Launch at login requires user approval")
                return false
            @unknown default:
                logger.warning("Unknown launch at login status: \(status.rawValue)")
                return false
            }
        }
    }
}