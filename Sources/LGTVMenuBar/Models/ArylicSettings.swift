import Foundation

/// Configuration settings for Arylic audio device integration.
public struct ArylicSettings: Codable, Sendable, Equatable {
    /// Arylic device hostname or IP address
    public let host: String
    
    /// Arylic device TCP API port
    public let port: Int
    
    /// Network timeout for API requests
    public let timeout: TimeInterval
    
    // MARK: - UserDefaults Keys
    
    /// UserDefaults key for Arylic host
    public static let hostKey = "arylicHost"
    
    /// UserDefaults key for Arylic port
    public static let portKey = "arylicPort"
    
    /// UserDefaults key for Arylic timeout
    public static let timeoutKey = "arylicTimeout"
    
    // MARK: - Initialization
    
    /// Creates a new Arylic settings configuration.
    ///
    /// - Parameters:
    ///   - host: Hostname or IP address of the Arylic device
    ///   - port: TCP API port (default: 8899)
    ///   - timeout: Network timeout in seconds (default: 5.0)
    public init(host: String, port: Int = 8899, timeout: TimeInterval = 5.0) {
        self.host = host
        self.port = port
        self.timeout = timeout
    }
}
