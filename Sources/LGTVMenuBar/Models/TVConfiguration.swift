import Foundation

/// Configuration for a TV connection
public struct TVConfiguration: Codable, Identifiable, Sendable {
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
        enablePCMode: Bool = false
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
    }
}
