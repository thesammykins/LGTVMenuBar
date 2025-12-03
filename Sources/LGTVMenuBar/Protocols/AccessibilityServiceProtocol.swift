import Foundation
import ApplicationServices

/// Protocol abstracting accessibility permission checks for testability
@preconcurrency public protocol AccessibilityServiceProtocol: Sendable {
    /// Check if process is trusted for accessibility
    func isProcessTrusted() -> Bool
    
    /// Request accessibility permission with a prompt
    /// - Returns: Whether process is trusted after the request
    func requestPermission() -> Bool
}

/// Default implementation using AXIsProcessTrusted
@preconcurrency public struct SystemAccessibilityService: AccessibilityServiceProtocol {
    public init() {}
    
    public func isProcessTrusted() -> Bool {
        AXIsProcessTrusted()
    }
    
    public func requestPermission() -> Bool {
        // Use a simple approach - create options dictionary with known key
        // The kAXTrustedCheckOptionPrompt is a CFString constant
        let promptKey = "AXTrustedCheckOptionPrompt" as CFString
        let options = [promptKey: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}