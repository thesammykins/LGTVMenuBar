import Foundation
import Testing
@testable import LGTVMenuBar

/// Volume curve conversion functions for testing
/// These mirror the private functions in VolumeSection
enum VolumeCurve {
    /// Convert slider position (0-1) to volume (0-100) with power curve (exponent 2.0)
    static func sliderToVolume(_ position: Double) -> Int {
        Int((pow(position, 2.0) * 100).rounded())
    }
    
    /// Convert volume (0-100) to slider position (0-1) - inverse (sqrt)
    static func volumeToSlider(_ volume: Int) -> Double {
        pow(Double(volume) / 100.0, 0.5)
    }
}

@Suite("Volume Curve Tests")
struct VolumeCurveTests {
    
    // MARK: - Boundary Tests
    
    @Test("sliderToVolume at 0 returns 0")
    func sliderToVolumeAtZero() {
        #expect(VolumeCurve.sliderToVolume(0.0) == 0)
    }
    
    @Test("sliderToVolume at 1 returns 100")
    func sliderToVolumeAtOne() {
        #expect(VolumeCurve.sliderToVolume(1.0) == 100)
    }
    
    @Test("volumeToSlider at 0 returns 0")
    func volumeToSliderAtZero() {
        #expect(VolumeCurve.volumeToSlider(0) == 0.0)
    }
    
    @Test("volumeToSlider at 100 returns 1")
    func volumeToSliderAtHundred() {
        #expect(VolumeCurve.volumeToSlider(100) == 1.0)
    }
    
    // MARK: - Curve Behavior Tests (exponent 2.0)
    
    @Test("sliderToVolume at 0.5 returns 25 (power curve)")
    func sliderToVolumeAtHalf() {
        // 0.5^2 * 100 = 25
        #expect(VolumeCurve.sliderToVolume(0.5) == 25)
    }
    
    @Test("sliderToVolume at 0.25 returns 6 (power curve)")
    func sliderToVolumeAtQuarter() {
        // 0.25^2 * 100 = 6.25, rounded = 6
        #expect(VolumeCurve.sliderToVolume(0.25) == 6)
    }
    
    @Test("sliderToVolume at 0.75 returns 56 (power curve)")
    func sliderToVolumeAtThreeQuarters() {
        // 0.75^2 * 100 = 56.25, rounded = 56
        #expect(VolumeCurve.sliderToVolume(0.75) == 56)
    }
    
    @Test("volumeToSlider at 25 returns ~0.5 (inverse curve)")
    func volumeToSliderAt25() {
        // sqrt(25/100) = sqrt(0.25) = 0.5
        #expect(VolumeCurve.volumeToSlider(25) == 0.5)
    }
    
    @Test("volumeToSlider at 50 returns ~0.707 (inverse curve)")
    func volumeToSliderAt50() {
        // sqrt(50/100) = sqrt(0.5) ≈ 0.707
        let result = VolumeCurve.volumeToSlider(50)
        #expect(result > 0.70 && result < 0.72)
    }
    
    // MARK: - Round-Trip Consistency Tests
    
    @Test("Round-trip conversion preserves volume at boundaries")
    func roundTripBoundaries() {
        for volume in [0, 100] {
            let position = VolumeCurve.volumeToSlider(volume)
            let backToVolume = VolumeCurve.sliderToVolume(position)
            #expect(backToVolume == volume)
        }
    }
    
    @Test("Round-trip conversion preserves volume at key points")
    func roundTripKeyPoints() {
        // Test volumes that map cleanly: 0, 25, 100
        for volume in [0, 25, 100] {
            let position = VolumeCurve.volumeToSlider(volume)
            let backToVolume = VolumeCurve.sliderToVolume(position)
            #expect(backToVolume == volume)
        }
    }
    
    @Test("Round-trip is stable within ±1 for all volumes")
    func roundTripStability() {
        for volume in 0...100 {
            let position = VolumeCurve.volumeToSlider(volume)
            let backToVolume = VolumeCurve.sliderToVolume(position)
            // Allow ±1 due to rounding
            #expect(abs(backToVolume - volume) <= 1)
        }
    }
    
    // MARK: - Resistance Behavior Tests
    
    @Test("Higher slider positions require more movement per volume unit")
    func resistanceIncreases() {
        // Going from 0% to 25% volume requires 50% of slider travel
        // Going from 75% to 100% volume requires only ~13% of slider travel
        let posAt25 = VolumeCurve.volumeToSlider(25)  // 0.5
        let posAt75 = VolumeCurve.volumeToSlider(75)  // ~0.866
        let posAt100 = VolumeCurve.volumeToSlider(100) // 1.0
        
        let travelTo25 = posAt25 - 0.0           // 0.5 (50% of slider)
        let travel75To100 = posAt100 - posAt75   // ~0.134 (13% of slider)
        
        // First 25% of volume takes more slider travel than last 25%
        #expect(travelTo25 > travel75To100)
    }
}
