import Foundation

/// What the TV is currently showing in the foreground.
///
/// An HDMI input and a streaming app are different things to automation: powering the TV off or
/// switching inputs is only safe when the Mac's own input is in front.
public enum TVForeground: Equatable, Sendable {
    case input(TVInputType)
    case app(String)
    case unknown

    /// The input in front, or nil when an app (or nothing known) is showing.
    public var input: TVInputType? {
        if case .input(let input) = self { return input }
        return nil
    }

    public var diagnosticDescription: String {
        switch self {
        case .input(let input): return "input:\(input.rawValue)"
        case .app(let appId): return "app:\(appId)"
        case .unknown: return "unknown"
        }
    }

    /// System surfaces that appear over whatever was showing and are not a viewing choice. A Mac
    /// whose display has gone to sleep leaves the TV on its screensaver; that must not stop the
    /// TV being switched off with the Mac.
    static let systemSurfaceAppIDs: Set<String> = ["com.webos.app.screensaver", "com.webos.app.home"]

    /// Maps a webOS foreground app id. Returns nil for an empty id (reported during
    /// transitions) and for system surfaces; neither says what the viewer is watching, so the
    /// caller keeps what it knew before.
    public static func from(appId: String) -> TVForeground? {
        let trimmed = appId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lowercased = trimmed.lowercased()
        guard !systemSurfaceAppIDs.contains(lowercased) else { return nil }
        if let input = TVInputType.allCases.first(where: { $0.appId.lowercased() == lowercased }) {
            return .input(input)
        }
        return .app(trimmed)
    }
}

/// One entry of the TV's external input list.
public struct TVInputInfo: Equatable, Sendable, Identifiable {
    public let id: String
    public let label: String
    public let icon: String
    public let isConnected: Bool

    public init(id: String, label: String, icon: String, isConnected: Bool) {
        self.id = id
        self.label = label
        self.icon = icon
        self.isConnected = isConnected
    }

    /// The TV marks an input as a PC by giving it the PC icon.
    public var isPCMode: Bool { Self.iconIndicatesPC(icon) }

    /// The icon arrives as a bare file name from the TV's input manager ("pc.png") and as a
    /// full URL over the pairing connection ("https://<tv>:3001/resources/<hash>/pc.png"), so
    /// only the file name is compared; a substring test could match the host or the hash.
    public static func iconIndicatesPC(_ icon: String) -> Bool {
        let fileName = icon.split(separator: "/").last.map(String.init) ?? icon
        return fileName.lowercased().split(separator: ".").first == "pc"
    }
}
