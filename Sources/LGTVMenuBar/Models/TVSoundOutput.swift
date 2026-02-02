import Foundation

/// Represents LG WebOS TV sound output types
/// Used to determine UI behavior (volume slider vs +/- buttons for external outputs)
public enum TVSoundOutput: String, CaseIterable, Sendable, Equatable {
    case tvSpeaker = "tv_speaker"
    case externalArc = "external_arc"
    case externalOptical = "external_optical"
    case lineout = "lineout"
    case headphone = "headphone"
    case bluetooth = "tv_speaker_bluetooth"
    case externalSpeaker = "tv_external_speaker"
    case speakerHeadphone = "tv_speaker_headphone"
    case unknown = "unknown"
    
    /// Whether this output supports precise volume control via slider
    /// Internal outputs (TV speaker, headphone, etc.) support sliders
    /// External outputs (ARC, optical, etc.) only support +/- buttons
    public var supportsVolumeSlider: Bool {
        switch self {
        case .tvSpeaker, .headphone, .lineout, .speakerHeadphone:
            return true
        case .externalArc, .externalOptical, .bluetooth, .externalSpeaker, .unknown:
            return false
        }
    }
    
    /// Human-readable display name for UI
    public var displayName: String {
        switch self {
        case .tvSpeaker: return "TV Speaker"
        case .externalArc: return "HDMI ARC"
        case .externalOptical: return "Optical"
        case .lineout: return "Line Out"
        case .headphone: return "Headphone"
        case .bluetooth: return "Bluetooth"
        case .externalSpeaker: return "External Speaker"
        case .speakerHeadphone: return "TV Speaker + Headphone"
        case .unknown: return "Unknown"
        }
    }
    
    /// Creates a TVSoundOutput from a WebOS API string value
    /// Returns .unknown for unrecognized values
    public static func fromAPIValue(_ value: String) -> TVSoundOutput {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")

        switch normalized {
        case "tv_speaker", "tv_speakers", "speaker":
            return .tvSpeaker
        case "external_arc", "earc", "arc", "hdmi_arc", "hdmi_earc":
            return .externalArc
        case "external_optical", "optical", "spdif":
            return .externalOptical
        case "lineout", "line_out":
            return .lineout
        case "headphone", "headphones", "headphone_out", "headphone_output":
            return .headphone
        case "tv_speaker_bluetooth", "bluetooth", "bt", "bt_soundbar":
            return .bluetooth
        case "external_speaker", "tv_external_speaker", "soundbar":
            return .externalSpeaker
        case "tv_speaker_headphone":
            return .speakerHeadphone
        default:
            return TVSoundOutput(rawValue: normalized) ?? .unknown
        }
    }
}
