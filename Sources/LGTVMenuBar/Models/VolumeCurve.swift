import Foundation

/// Maps the volume slider's position to a TV volume.
///
/// The curve is quadratic so most of the slider's travel covers the quiet end, where a step of
/// one is audible, and a small nudge near the top cannot make the TV very loud.
public enum VolumeCurve {
    /// Slider position (0...1) to volume (0...100).
    public static func sliderToVolume(_ position: Double) -> Int {
        Int((pow(min(max(position, 0), 1), 2.0) * 100).rounded())
    }

    /// Volume (0...100) to slider position (0...1).
    public static func volumeToSlider(_ volume: Int) -> Double {
        pow(Double(min(max(volume, 0), 100)) / 100.0, 0.5)
    }
}
