import Foundation

@preconcurrency
public protocol LaunchAtLoginManagerProtocol: Sendable {
    func enableLaunchAtLogin() async throws
    func disableLaunchAtLogin() async throws
    func isLaunchAtLoginEnabled() async throws -> Bool
}
