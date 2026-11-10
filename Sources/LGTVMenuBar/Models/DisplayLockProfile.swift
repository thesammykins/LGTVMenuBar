import Foundation

/// A macOS display mode, as much of it as the lock pins.
public struct DisplayModeSpec: Codable, Equatable, Hashable, Sendable {
    public var pixelWidth: Int
    public var pixelHeight: Int
    /// Width in points; differs from `pixelWidth` for HiDPI modes.
    public var pointWidth: Int
    public var pointHeight: Int
    public var refreshRate: Double

    public init(pixelWidth: Int, pixelHeight: Int, pointWidth: Int, pointHeight: Int, refreshRate: Double) {
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.pointWidth = pointWidth
        self.pointHeight = pointHeight
        self.refreshRate = refreshRate
    }

    public var isHiDPI: Bool { pixelWidth > pointWidth }

    public var displayName: String {
        let rate = refreshRate.rounded() == refreshRate ? String(Int(refreshRate)) : String(format: "%.2f", refreshRate)
        let scale = isHiDPI ? " (HiDPI)" : ""
        return "\(pointWidth) × \(pointHeight)\(scale), \(rate) Hz"
    }

    /// Refresh rates are reported with rounding noise (59.94 vs 59.940002).
    public func matches(_ other: DisplayModeSpec) -> Bool {
        pixelWidth == other.pixelWidth && pixelHeight == other.pixelHeight
            && pointWidth == other.pointWidth && pointHeight == other.pointHeight
            && abs(refreshRate - other.refreshRate) < 0.05
    }
}

/// Display configuration that is enforced only while the TV shows one particular input.
public struct DisplayLockProfile: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    /// The TV input this profile belongs to (e.g. "HDMI_1"). Empty means the preferred input.
    public var inputID: String
    /// Stable identifier of the macOS display that is the TV. Nil means "detect the LG display".
    public var displayUUID: String?
    public var mode: DisplayModeSpec?
    /// Nil leaves HDR alone.
    public var hdrEnabled: Bool?
    /// Keep the TV's input labelled as a PC (4:4:4 chroma, low latency).
    public var enforcePCMode: Bool
    /// TV picture mode to hold (e.g. "game", "expert2"). Nil leaves it alone.
    public var pictureMode: String?

    public init(
        isEnabled: Bool = false,
        inputID: String = "",
        displayUUID: String? = nil,
        mode: DisplayModeSpec? = nil,
        hdrEnabled: Bool? = nil,
        enforcePCMode: Bool = false,
        pictureMode: String? = nil
    ) {
        self.isEnabled = isEnabled
        self.inputID = inputID
        self.displayUUID = displayUUID
        self.mode = mode
        self.hdrEnabled = hdrEnabled
        self.enforcePCMode = enforcePCMode
        self.pictureMode = pictureMode
    }

    public func effectiveInputID(preferredInput: String) -> String {
        inputID.isEmpty ? preferredInput : inputID
    }

    /// True when the profile would not change anything even if enabled.
    public var isEmpty: Bool {
        mode == nil && hdrEnabled == nil && !enforcePCMode && pictureMode == nil
    }
}
