import Foundation

/// Media key types that can be captured (volume only)
public enum MediaKey: String, CaseIterable, Sendable {
    case volumeUp = "volumeUp"
    case volumeDown = "volumeDown"
    case mute = "mute"
}