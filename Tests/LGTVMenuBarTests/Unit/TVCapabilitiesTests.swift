import Testing
import Foundation
@testable import LGTVMenuBar

@Suite("TVCapabilities Tests")
@MainActor
struct TVCapabilitiesTests {
    
    // MARK: - parseChipType Tests
    
    @Test("parseChipType extracts chip from valid 2022 OLED model name")
    func parseChipType2022OLED() {
        let result = TVCapabilities.parseChipType(from: "HE_DTV_W22O_AFABATAA")
        #expect(result != nil)
        #expect(result?.chip == "W22O")
        #expect(result?.year == 2022)
    }
    
    @Test("parseChipType extracts chip from valid 2021 OLED model name")
    func parseChipType2021OLED() {
        let result = TVCapabilities.parseChipType(from: "HE_DTV_W21O_AFABATAA")
        #expect(result != nil)
        #expect(result?.chip == "W21O")
        #expect(result?.year == 2021)
    }
    
    @Test("parseChipType extracts chip from valid 2020 OLED model name")
    func parseChipType2020OLED() {
        let result = TVCapabilities.parseChipType(from: "HE_DTV_W20O_AFABATAA")
        #expect(result != nil)
        #expect(result?.chip == "W20O")
        #expect(result?.year == 2020)
    }
    
    @Test("parseChipType extracts chip from 2023 G-series model")
    func parseChipType2023GSeries() {
        let result = TVCapabilities.parseChipType(from: "HE_DTV_W23G_AFABATAA")
        #expect(result != nil)
        #expect(result?.chip == "W23G")
        #expect(result?.year == 2023)
    }
    
    @Test("parseChipType extracts chip from LCD model (H suffix)")
    func parseChipTypeLCD() {
        let result = TVCapabilities.parseChipType(from: "HE_DTV_W22H_AFABATAA")
        #expect(result != nil)
        #expect(result?.chip == "W22H")
        #expect(result?.year == 2022)
    }
    
    @Test("parseChipType extracts chip from 2024 model")
    func parseChipType2024() {
        let result = TVCapabilities.parseChipType(from: "HE_DTV_W24O_AFABATAA")
        #expect(result != nil)
        #expect(result?.chip == "W24O")
        #expect(result?.year == 2024)
    }
    
    @Test("parseChipType extracts chip from 2025 model")
    func parseChipType2025() {
        let result = TVCapabilities.parseChipType(from: "HE_DTV_W25O_AFABATAA")
        #expect(result != nil)
        #expect(result?.chip == "W25O")
        #expect(result?.year == 2025)
    }
    
    @Test("parseChipType returns nil for invalid prefix")
    func parseChipTypeInvalidPrefix() {
        let result = TVCapabilities.parseChipType(from: "INVALID_W22O_AFABATAA")
        #expect(result == nil)
    }
    
    @Test("parseChipType returns nil for empty string")
    func parseChipTypeEmptyString() {
        let result = TVCapabilities.parseChipType(from: "")
        #expect(result == nil)
    }
    
    @Test("parseChipType returns nil for too short string")
    func parseChipTypeTooShort() {
        let result = TVCapabilities.parseChipType(from: "HE_DTV_W2")
        #expect(result == nil)
    }
    
    @Test("parseChipType returns nil for missing W prefix in chip")
    func parseChipTypeMissingW() {
        let result = TVCapabilities.parseChipType(from: "HE_DTV_X22O_AFABATAA")
        #expect(result == nil)
    }
    
    @Test("parseChipType returns nil for non-numeric year")
    func parseChipTypeNonNumericYear() {
        let result = TVCapabilities.parseChipType(from: "HE_DTV_WXXO_AFABATAA")
        #expect(result == nil)
    }
    
    // MARK: - Observable Properties Tests
    
    @Test("initializes with default empty values")
    func initDefaultValues() {
        let capabilities = TVCapabilities()
        
        #expect(capabilities.modelName == "")
        #expect(capabilities.chipType == "")
        #expect(capabilities.modelYear == 0)
        #expect(capabilities.webOSVersion == "")
        #expect(capabilities.usesSSL == true)
    }
    
    @Test("properties are observable and can be set")
    func propertiesSettable() {
        let capabilities = TVCapabilities()
        
        capabilities.modelName = "HE_DTV_W22O_AFABATAA"
        capabilities.chipType = "W22O"
        capabilities.modelYear = 2022
        capabilities.webOSVersion = "22.10.0"
        capabilities.usesSSL = true
        
        #expect(capabilities.modelName == "HE_DTV_W22O_AFABATAA")
        #expect(capabilities.chipType == "W22O")
        #expect(capabilities.modelYear == 2022)
        #expect(capabilities.webOSVersion == "22.10.0")
        #expect(capabilities.usesSSL == true)
    }
    
    // MARK: - Year Range Tests (2020-2025)
    
    @Test("parseChipType handles all supported years", arguments: [20, 21, 22, 23, 24, 25])
    func parseChipTypeAllYears(yearSuffix: Int) {
        let modelName = "HE_DTV_W\(yearSuffix)O_AFABATAA"
        let result = TVCapabilities.parseChipType(from: modelName)
        
        #expect(result != nil)
        #expect(result?.year == 2000 + yearSuffix)
    }
    
    // MARK: - Chip Type Suffix Tests
    
    @Test("parseChipType handles all chip suffixes", arguments: ["O", "G", "H"])
    func parseChipTypeAllSuffixes(suffix: String) {
        let modelName = "HE_DTV_W22\(suffix)_AFABATAA"
        let result = TVCapabilities.parseChipType(from: modelName)
        
        #expect(result != nil)
        #expect(result?.chip == "W22\(suffix)")
    }
    
    // MARK: - SSL Requirement by Year
    
    @Test("2022+ models should use SSL by default")
    func sslRequirementFor2022Plus() {
        let capabilities = TVCapabilities()
        capabilities.modelYear = 2022
        
        // Default usesSSL is true, appropriate for 2022+
        #expect(capabilities.usesSSL == true)
    }
}
