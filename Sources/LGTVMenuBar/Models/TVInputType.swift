import Foundation

/// Represents available TV input types for LG WebOS TVs
public enum TVInputType: String, CaseIterable, Sendable {
    case hdmi1 = "HDMI_1"
    case hdmi2 = "HDMI_2"
    case hdmi3 = "HDMI_3"
    case hdmi4 = "HDMI_4"
    case displayPort1 = "DP_1"
    case displayPort2 = "DP_2"
    case usbC1 = "USBC_1"
    case usbC2 = "USBC_2"
    
    /// WebOS app identifier for launching this input
    public var appId: String {
        let normalized = rawValue.lowercased().replacingOccurrences(of: "_", with: "")
        return "com.webos.app.\(normalized)"
    }
    
    /// Human-readable display name
    public var displayName: String {
        switch self {
        case .hdmi1: return "HDMI 1"
        case .hdmi2: return "HDMI 2"
        case .hdmi3: return "HDMI 3"
        case .hdmi4: return "HDMI 4"
        case .displayPort1: return "DisplayPort 1"
        case .displayPort2: return "DisplayPort 2"
        case .usbC1: return "USB-C 1"
        case .usbC2: return "USB-C 2"
        }
    }
}
