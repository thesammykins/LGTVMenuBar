import Foundation

/// TV capabilities detected from software info
@MainActor
@Observable
public final class TVCapabilities {
    public var modelName: String = ""
    public var chipType: String = ""
    public var modelYear: Int = 0
    public var webOSVersion: String = ""
    public var usesSSL: Bool = true
    
    /// Maps input IDs to their current icon (e.g., "HDMI_1": "pc.png")
    public var inputIcons: [String: String] = [:]
    
    public init() {}
    
    public init(modelName: String = "", chipType: String = "", modelYear: Int = 0, webOSVersion: String = "", usesSSL: Bool = true) {
        self.modelName = modelName
        self.chipType = chipType
        self.modelYear = modelYear
        self.webOSVersion = webOSVersion
        self.usesSSL = usesSSL
    }
    
    /// Parse chip type and year from model name
    /// Format: "HE_DTV_W22O_AFABATAA" -> chip: "W22O", year: 2022
    public static func parseChipType(from modelName: String) -> (chip: String, year: Int)? {
        // Validate prefix
        guard modelName.hasPrefix("HE_DTV_") else { return nil }
        
        // Need at least 11 characters for "HE_DTV_W22O"
        guard modelName.count >= 11 else { return nil }
        
        // Extract chip code (4 characters after "HE_DTV_")
        let startIndex = modelName.index(modelName.startIndex, offsetBy: 7)
        let endIndex = modelName.index(startIndex, offsetBy: 4)
        let chip = String(modelName[startIndex..<endIndex])
        
        // Validate chip format: starts with W, followed by 2 digits, then a letter
        guard chip.hasPrefix("W") else { return nil }
        
        // Extract year digits
        let yearStartIndex = chip.index(chip.startIndex, offsetBy: 1)
        let yearEndIndex = chip.index(yearStartIndex, offsetBy: 2)
        let yearString = String(chip[yearStartIndex..<yearEndIndex])
        
        guard let yearDigits = Int(yearString) else { return nil }
        
        let year = 2000 + yearDigits
        
        return (chip, year)
    }
}
