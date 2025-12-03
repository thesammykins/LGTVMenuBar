import Foundation
import AppKit

/// Information about a connected screen
public struct ScreenInfo: Sendable, Equatable {
    public let localizedName: String?
    public let frame: CGRect
    
    public init(localizedName: String?, frame: CGRect) {
        self.localizedName = localizedName
        self.frame = frame
    }
}

/// Protocol abstracting screen detection for testability
public protocol ScreenServiceProtocol: Sendable {
    /// Get all connected screens
    var screens: [ScreenInfo] { get }
    
    /// Check if an LG TV is connected as a display
    func isLGTVConnected() -> Bool
}

/// Default implementation using NSScreen
public struct SystemScreenService: ScreenServiceProtocol {
    public init() {}
    
    public var screens: [ScreenInfo] {
        NSScreen.screens.map { screen in
            ScreenInfo(localizedName: screen.localizedName, frame: screen.frame)
        }
    }
    
    public func isLGTVConnected() -> Bool {
        let tvIdentifiers = ["LG TV", "LG TV SSCR2"]
        return screens.contains { screen in
            guard let name = screen.localizedName else { return false }
            return tvIdentifiers.contains(where: { name.contains($0) })
        }
    }
}
