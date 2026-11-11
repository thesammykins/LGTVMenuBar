import Foundation

/// Configuration for a TV connection
public struct TVConfiguration: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public var name: String
    public var ipAddress: String
    public var macAddress: String
    public var preferredInput: String
    public var autoConnectOnLaunch: Bool
    public var wakeWithMac: Bool
    public var sleepWithMac: Bool
    public var switchInputOnWake: Bool
    public var enablePCMode: Bool
    public var wakeBroadcastAddress: String?
    public var wakePort: Int?
    public var wakeTimeoutSeconds: Double?
    /// Opening the menu while the TV is off powers it on. Only applies with `wakeWithMac`.
    public var wakeOnMenuOpen: Bool
    /// Optional shell access to a rooted TV.
    public var rootAccess: RootAccessSettings
    /// Display configuration pinned while the TV shows the Mac's input.
    public var displayLock: DisplayLockProfile
    /// Switch the TV off for a due pixel refresh while the Mac is locked or its display sleeps,
    /// and let that refresh finish. Needs root access to know when a refresh is due.
    public var refreshPixelsDuringDowntime: Bool
    /// Hours of the day that the above is limited to, if any.
    public var panelCareSchedule: PanelCareSchedule

    public init(
        id: UUID = UUID(),
        name: String,
        ipAddress: String,
        macAddress: String,
        preferredInput: String = "HDMI_1",
        autoConnectOnLaunch: Bool = true,
        wakeWithMac: Bool = true,
        sleepWithMac: Bool = true,
        switchInputOnWake: Bool = false,
        enablePCMode: Bool = false,
        wakeBroadcastAddress: String? = nil,
        wakePort: Int? = nil,
        wakeTimeoutSeconds: Double? = nil,
        wakeOnMenuOpen: Bool = true,
        rootAccess: RootAccessSettings = RootAccessSettings(),
        displayLock: DisplayLockProfile = DisplayLockProfile(),
        refreshPixelsDuringDowntime: Bool = false,
        panelCareSchedule: PanelCareSchedule = PanelCareSchedule()
    ) {
        self.id = id
        self.name = name
        self.ipAddress = ipAddress
        self.macAddress = macAddress
        self.preferredInput = preferredInput
        self.autoConnectOnLaunch = autoConnectOnLaunch
        self.wakeWithMac = wakeWithMac
        self.sleepWithMac = sleepWithMac
        self.switchInputOnWake = switchInputOnWake
        self.enablePCMode = enablePCMode
        self.wakeBroadcastAddress = wakeBroadcastAddress
        self.wakePort = wakePort
        self.wakeTimeoutSeconds = wakeTimeoutSeconds
        self.wakeOnMenuOpen = wakeOnMenuOpen
        self.rootAccess = rootAccess
        self.displayLock = displayLock
        self.refreshPixelsDuringDowntime = refreshPixelsDuringDowntime
        self.panelCareSchedule = panelCareSchedule
    }

    // Decoding is written out so configurations saved by older releases, which lack the newer
    // keys, keep loading with defaults instead of being discarded.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        ipAddress = try container.decode(String.self, forKey: .ipAddress)
        macAddress = try container.decode(String.self, forKey: .macAddress)
        preferredInput = try container.decodeIfPresent(String.self, forKey: .preferredInput) ?? "HDMI_1"
        autoConnectOnLaunch = try container.decodeIfPresent(Bool.self, forKey: .autoConnectOnLaunch) ?? true
        wakeWithMac = try container.decodeIfPresent(Bool.self, forKey: .wakeWithMac) ?? true
        sleepWithMac = try container.decodeIfPresent(Bool.self, forKey: .sleepWithMac) ?? true
        switchInputOnWake = try container.decodeIfPresent(Bool.self, forKey: .switchInputOnWake) ?? false
        enablePCMode = try container.decodeIfPresent(Bool.self, forKey: .enablePCMode) ?? false
        wakeBroadcastAddress = try container.decodeIfPresent(String.self, forKey: .wakeBroadcastAddress)
        wakePort = try container.decodeIfPresent(Int.self, forKey: .wakePort)
        wakeTimeoutSeconds = try container.decodeIfPresent(Double.self, forKey: .wakeTimeoutSeconds)
        wakeOnMenuOpen = try container.decodeIfPresent(Bool.self, forKey: .wakeOnMenuOpen) ?? true
        rootAccess = try container.decodeIfPresent(RootAccessSettings.self, forKey: .rootAccess) ?? RootAccessSettings()
        displayLock = try container.decodeIfPresent(DisplayLockProfile.self, forKey: .displayLock) ?? DisplayLockProfile()
        refreshPixelsDuringDowntime = try container.decodeIfPresent(Bool.self, forKey: .refreshPixelsDuringDowntime) ?? false
        panelCareSchedule = try container.decodeIfPresent(PanelCareSchedule.self, forKey: .panelCareSchedule) ?? PanelCareSchedule()
    }
}
