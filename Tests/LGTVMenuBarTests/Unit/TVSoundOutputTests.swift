import Testing
@testable import LGTVMenuBar

@Suite("TVSoundOutput Tests")
struct TVSoundOutputTests {
    
    // MARK: - rawValue Tests
    
    @Test("rawValue for tvSpeaker is correct")
    func tvSpeakerRawValue() {
        #expect(TVSoundOutput.tvSpeaker.rawValue == "tv_speaker")
    }
    
    @Test("rawValue for externalArc is correct")
    func externalArcRawValue() {
        #expect(TVSoundOutput.externalArc.rawValue == "external_arc")
    }
    
    @Test("rawValue for externalOptical is correct")
    func externalOpticalRawValue() {
        #expect(TVSoundOutput.externalOptical.rawValue == "external_optical")
    }
    
    @Test("rawValue for lineout is correct")
    func lineoutRawValue() {
        #expect(TVSoundOutput.lineout.rawValue == "lineout")
    }
    
    @Test("rawValue for headphone is correct")
    func headphoneRawValue() {
        #expect(TVSoundOutput.headphone.rawValue == "headphone")
    }
    
    @Test("rawValue for bluetooth is correct")
    func bluetoothRawValue() {
        #expect(TVSoundOutput.bluetooth.rawValue == "tv_speaker_bluetooth")
    }
    
    @Test("rawValue for externalSpeaker is correct")
    func externalSpeakerRawValue() {
        #expect(TVSoundOutput.externalSpeaker.rawValue == "tv_external_speaker")
    }
    
    @Test("rawValue for speakerHeadphone is correct")
    func speakerHeadphoneRawValue() {
        #expect(TVSoundOutput.speakerHeadphone.rawValue == "tv_speaker_headphone")
    }
    
    @Test("rawValue for unknown is correct")
    func unknownRawValue() {
        #expect(TVSoundOutput.unknown.rawValue == "unknown")
    }
    
    // MARK: - supportsVolumeSlider Tests
    
    @Test("tvSpeaker supports volume slider")
    func tvSpeakerSupportsVolumeSlider() {
        #expect(TVSoundOutput.tvSpeaker.supportsVolumeSlider == true)
    }
    
    @Test("headphone supports volume slider")
    func headphoneSupportsVolumeSlider() {
        #expect(TVSoundOutput.headphone.supportsVolumeSlider == true)
    }
    
    @Test("lineout supports volume slider")
    func lineoutSupportsVolumeSlider() {
        #expect(TVSoundOutput.lineout.supportsVolumeSlider == true)
    }
    
    @Test("speakerHeadphone supports volume slider")
    func speakerHeadphoneSupportsVolumeSlider() {
        #expect(TVSoundOutput.speakerHeadphone.supportsVolumeSlider == true)
    }
    
    @Test("externalArc does not support volume slider")
    func externalArcDoesNotSupportVolumeSlider() {
        #expect(TVSoundOutput.externalArc.supportsVolumeSlider == false)
    }
    
    @Test("externalOptical does not support volume slider")
    func externalOpticalDoesNotSupportVolumeSlider() {
        #expect(TVSoundOutput.externalOptical.supportsVolumeSlider == false)
    }
    
    @Test("bluetooth does not support volume slider")
    func bluetoothDoesNotSupportVolumeSlider() {
        #expect(TVSoundOutput.bluetooth.supportsVolumeSlider == false)
    }
    
    @Test("externalSpeaker does not support volume slider")
    func externalSpeakerDoesNotSupportVolumeSlider() {
        #expect(TVSoundOutput.externalSpeaker.supportsVolumeSlider == false)
    }
    
    @Test("unknown does not support volume slider")
    func unknownDoesNotSupportVolumeSlider() {
        #expect(TVSoundOutput.unknown.supportsVolumeSlider == false)
    }
    
    // MARK: - displayName Tests
    
    @Test("displayName for tvSpeaker is correct")
    func tvSpeakerDisplayName() {
        #expect(TVSoundOutput.tvSpeaker.displayName == "TV Speaker")
    }
    
    @Test("displayName for externalArc is correct")
    func externalArcDisplayName() {
        #expect(TVSoundOutput.externalArc.displayName == "HDMI ARC")
    }
    
    @Test("displayName for externalOptical is correct")
    func externalOpticalDisplayName() {
        #expect(TVSoundOutput.externalOptical.displayName == "Optical")
    }
    
    @Test("displayName for lineout is correct")
    func lineoutDisplayName() {
        #expect(TVSoundOutput.lineout.displayName == "Line Out")
    }
    
    @Test("displayName for headphone is correct")
    func headphoneDisplayName() {
        #expect(TVSoundOutput.headphone.displayName == "Headphone")
    }
    
    @Test("displayName for bluetooth is correct")
    func bluetoothDisplayName() {
        #expect(TVSoundOutput.bluetooth.displayName == "Bluetooth")
    }
    
    @Test("displayName for externalSpeaker is correct")
    func externalSpeakerDisplayName() {
        #expect(TVSoundOutput.externalSpeaker.displayName == "External Speaker")
    }
    
    @Test("displayName for speakerHeadphone is correct")
    func speakerHeadphoneDisplayName() {
        #expect(TVSoundOutput.speakerHeadphone.displayName == "TV Speaker + Headphone")
    }
    
    @Test("displayName for unknown is correct")
    func unknownDisplayName() {
        #expect(TVSoundOutput.unknown.displayName == "Unknown")
    }
    
    // MARK: - fromAPIValue Tests
    
    @Test("fromAPIValue returns correct case for tv_speaker")
    func fromAPIValueTvSpeaker() {
        #expect(TVSoundOutput.fromAPIValue("tv_speaker") == .tvSpeaker)
    }
    
    @Test("fromAPIValue returns correct case for external_arc")
    func fromAPIValueExternalArc() {
        #expect(TVSoundOutput.fromAPIValue("external_arc") == .externalArc)
    }
    
    @Test("fromAPIValue returns correct case for external_optical")
    func fromAPIValueExternalOptical() {
        #expect(TVSoundOutput.fromAPIValue("external_optical") == .externalOptical)
    }
    
    @Test("fromAPIValue returns correct case for lineout")
    func fromAPIValueLineout() {
        #expect(TVSoundOutput.fromAPIValue("lineout") == .lineout)
    }
    
    @Test("fromAPIValue returns correct case for headphone")
    func fromAPIValueHeadphone() {
        #expect(TVSoundOutput.fromAPIValue("headphone") == .headphone)
    }
    
    @Test("fromAPIValue returns correct case for tv_speaker_bluetooth")
    func fromAPIValueBluetooth() {
        #expect(TVSoundOutput.fromAPIValue("tv_speaker_bluetooth") == .bluetooth)
    }
    
    @Test("fromAPIValue returns correct case for tv_external_speaker")
    func fromAPIValueExternalSpeaker() {
        #expect(TVSoundOutput.fromAPIValue("tv_external_speaker") == .externalSpeaker)
    }
    
    @Test("fromAPIValue returns correct case for tv_speaker_headphone")
    func fromAPIValueSpeakerHeadphone() {
        #expect(TVSoundOutput.fromAPIValue("tv_speaker_headphone") == .speakerHeadphone)
    }
    
    @Test("fromAPIValue returns unknown for unrecognized value")
    func fromAPIValueUnrecognized() {
        #expect(TVSoundOutput.fromAPIValue("some_random_output") == .unknown)
    }
    
    @Test("fromAPIValue returns unknown for empty string")
    func fromAPIValueEmptyString() {
        #expect(TVSoundOutput.fromAPIValue("") == .unknown)
    }
    
    @Test("fromAPIValue returns unknown for case-mismatched value")
    func fromAPIValueCaseMismatch() {
        #expect(TVSoundOutput.fromAPIValue("TV_SPEAKER") == .tvSpeaker)
        #expect(TVSoundOutput.fromAPIValue("Tv_Speaker") == .tvSpeaker)
    }
    
    // MARK: - CaseIterable Tests
    
    @Test("allCases contains all 9 sound output types")
    func allCasesCount() {
        #expect(TVSoundOutput.allCases.count == 9)
    }
    
    @Test("allCases contains expected types")
    func allCasesContents() {
        let cases = TVSoundOutput.allCases
        #expect(cases.contains(.tvSpeaker))
        #expect(cases.contains(.externalArc))
        #expect(cases.contains(.externalOptical))
        #expect(cases.contains(.lineout))
        #expect(cases.contains(.headphone))
        #expect(cases.contains(.bluetooth))
        #expect(cases.contains(.externalSpeaker))
        #expect(cases.contains(.speakerHeadphone))
        #expect(cases.contains(.unknown))
    }
    
    // MARK: - Equatable Tests
    
    @Test("TVSoundOutput conforms to Equatable")
    func equatableConformance() {
        #expect(TVSoundOutput.tvSpeaker == TVSoundOutput.tvSpeaker)
        #expect(TVSoundOutput.tvSpeaker != TVSoundOutput.externalArc)
    }
    
    // MARK: - Init from rawValue Tests
    
    @Test("init from rawValue works for valid values")
    func initFromRawValue() {
        #expect(TVSoundOutput(rawValue: "tv_speaker") == .tvSpeaker)
        #expect(TVSoundOutput(rawValue: "external_arc") == .externalArc)
        #expect(TVSoundOutput(rawValue: "external_optical") == .externalOptical)
        #expect(TVSoundOutput(rawValue: "lineout") == .lineout)
        #expect(TVSoundOutput(rawValue: "headphone") == .headphone)
        #expect(TVSoundOutput(rawValue: "tv_speaker_bluetooth") == .bluetooth)
        #expect(TVSoundOutput(rawValue: "tv_external_speaker") == .externalSpeaker)
        #expect(TVSoundOutput(rawValue: "tv_speaker_headphone") == .speakerHeadphone)
        #expect(TVSoundOutput(rawValue: "unknown") == .unknown)
    }
    
    @Test("init from rawValue returns nil for invalid values")
    func initFromRawValueInvalid() {
        #expect(TVSoundOutput(rawValue: "INVALID") == nil)
        #expect(TVSoundOutput(rawValue: "TV_SPEAKER") == nil)  // uppercase
        #expect(TVSoundOutput(rawValue: "") == nil)
    }
}
