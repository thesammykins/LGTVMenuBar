import Foundation

/// Target device for volume control operations.
public enum VolumeControlTarget: String, Codable, Sendable {
    /// LG TV volume control
    case tv
    
    /// Arylic audio device volume control
    case arylic
}
