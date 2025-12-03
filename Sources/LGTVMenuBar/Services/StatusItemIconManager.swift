import AppKit
import Foundation

/// Manages the menu bar status item icon based on connection state
@MainActor
final class StatusItemIconManager {
    
    // MARK: - Icon Names
    
    /// Returns the appropriate SF Symbol name for a given connection state
    static func iconName(for state: ConnectionState) -> String {
        switch state {
        case .connected:
            return "tv.fill"
        case .disconnected:
            return "tv"
        case .connecting, .registering:
            // tv.badge.ellipsis may not exist - check availability
            if NSImage(systemSymbolName: "tv.badge.ellipsis", accessibilityDescription: nil) != nil {
                return "tv.badge.ellipsis"
            }
            return "tv"  // Fallback
        case .error:
            return "tv.slash"
        }
    }
    
    // MARK: - Icon Creation
    
    /// Creates an NSImage for the status item based on connection state
    static func icon(for state: ConnectionState) -> NSImage? {
        let symbolName = iconName(for: state)
        let image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: "LGTV Menu Bar - \(state.description)"
        )
        
        // Configure for menu bar appearance
        // isTemplate allows proper dark/light mode adaptation
        image?.isTemplate = true
        
        return image
    }
    
    // MARK: - Status Item Updates
    
    /// Updates a status item's button image based on connection state
    static func updateStatusItem(_ statusItem: NSStatusItem, for state: ConnectionState) {
        statusItem.button?.image = icon(for: state)
    }
}
