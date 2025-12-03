import Foundation

/// Protocol abstracting NotificationCenter operations for testability
public protocol NotificationCenterProtocol: AnyObject {
    /// Add an observer for a notification
    /// - Parameters:
    ///   - name: The notification name to observe
    ///   - object: The object to observe (optional)
    ///   - queue: The queue to execute the handler on
    ///   - handler: The handler to execute when the notification is received
    /// - Returns: An opaque observer object that can be used to remove the observer
    func addObserver(
        forName name: NSNotification.Name?,
        object: Any?,
        queue: OperationQueue?,
        using handler: @escaping @Sendable (Notification) -> Void
    ) -> any NSObjectProtocol
    
    /// Remove an observer
    /// - Parameter observer: The observer to remove
    func removeObserver(_ observer: Any)
}

// Conform NSWorkspace's NotificationCenter to our protocol
extension NotificationCenter: NotificationCenterProtocol {}
