import Foundation
import CoreGraphics

/// Protocol abstracting CGEventTap for testability
public protocol EventTapProtocol: AnyObject {
    /// Create and start the event tap
    /// - Parameter callback: The callback to invoke when media key events are received
    /// - Returns: Whether the tap was successfully created
    func start(callback: @escaping (MediaKeyEvent) -> Bool) -> Bool
    
    /// Stop and destroy the event tap
    func stop()
    
    /// Whether the event tap is currently active
    var isRunning: Bool { get }
}

/// Media key events that can be captured
public enum MediaKeyEvent: Sendable, Equatable {
    case volumeUp
    case volumeDown
    case mute
    case playPause
    case next
    case previous
}
