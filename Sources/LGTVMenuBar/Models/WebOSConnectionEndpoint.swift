import Foundation

/// WebSocket endpoint used for LG webOS SSAP control.
public struct WebOSConnectionEndpoint: Equatable, Sendable {
    public let scheme: String
    public let port: Int

    public var usesSSL: Bool {
        scheme == "wss"
    }

    public static let secure = WebOSConnectionEndpoint(scheme: "wss", port: 3001)
    public static let insecure = WebOSConnectionEndpoint(scheme: "ws", port: 3000)

    /// Newer LG firmware can reject insecure sockets, so always try secure first.
    public static let preferredOrder: [WebOSConnectionEndpoint] = [.secure, .insecure]

    public func url(for ipAddress: String) -> URL? {
        URL(string: "\(scheme)://\(ipAddress):\(port)/")
    }
}
