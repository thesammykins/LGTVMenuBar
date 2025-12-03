import Testing
import Foundation
@testable import LGTVMenuBar

@Suite("TVConfiguration Tests")
struct TVConfigurationTests {
    
    // MARK: - Initialization Tests
    
    @Test("initializes with all required properties")
    func initWithAllProperties() {
        let id = UUID()
        let config = TVConfiguration(
            id: id,
            name: "Living Room TV",
            ipAddress: "192.168.1.100",
            macAddress: "AA:BB:CC:DD:EE:FF",
            preferredInput: "HDMI_1",
            wakeWithMac: true,
            sleepWithMac: true,
            switchInputOnWake: true,
            enablePCMode: false
        )
        
        #expect(config.id == id)
        #expect(config.name == "Living Room TV")
        #expect(config.ipAddress == "192.168.1.100")
        #expect(config.macAddress == "AA:BB:CC:DD:EE:FF")
        #expect(config.preferredInput == "HDMI_1")
        #expect(config.wakeWithMac == true)
        #expect(config.sleepWithMac == true)
        #expect(config.switchInputOnWake == true)
        #expect(config.enablePCMode == false)
    }
    
    @Test("auto-generates UUID when not provided")
    func autoGeneratesUUID() {
        let config = TVConfiguration(
            name: "Test TV",
            ipAddress: "192.168.1.1",
            macAddress: "AA:BB:CC:DD:EE:FF"
        )
        
        #expect(config.id != UUID(uuidString: "00000000-0000-0000-0000-000000000000"))
    }
    
    @Test("uses default values for optional parameters")
    func defaultValues() {
        let config = TVConfiguration(
            name: "Test TV",
            ipAddress: "192.168.1.1",
            macAddress: "AA:BB:CC:DD:EE:FF"
        )
        
        #expect(config.preferredInput == "HDMI_1")
        #expect(config.wakeWithMac == true)
        #expect(config.sleepWithMac == true)
        #expect(config.switchInputOnWake == false)
        #expect(config.enablePCMode == false)
    }
    
    // MARK: - Codable Tests
    
    @Test("encodes to JSON correctly")
    func encodesToJSON() throws {
        let id = UUID()
        let config = TVConfiguration(
            id: id,
            name: "Test TV",
            ipAddress: "192.168.1.100",
            macAddress: "AA:BB:CC:DD:EE:FF",
            preferredInput: "HDMI_2",
            wakeWithMac: false,
            sleepWithMac: true,
            switchInputOnWake: true,
            enablePCMode: true
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(config)
        let json = String(data: data, encoding: .utf8)!
        
        #expect(json.contains("Test TV"))
        #expect(json.contains("192.168.1.100"))
        #expect(json.contains("AA:BB:CC:DD:EE:FF"))
        #expect(json.contains("HDMI_2"))
    }
    
    @Test("decodes from JSON correctly")
    func decodesFromJSON() throws {
        let id = UUID()
        let json = """
        {
            "id": "\(id.uuidString)",
            "name": "Bedroom TV",
            "ipAddress": "192.168.1.200",
            "macAddress": "11:22:33:44:55:66",
            "preferredInput": "HDMI_3",
            "wakeWithMac": false,
            "sleepWithMac": false,
            "switchInputOnWake": true,
            "enablePCMode": true
        }
        """
        
        let decoder = JSONDecoder()
        let data = json.data(using: .utf8)!
        let config = try decoder.decode(TVConfiguration.self, from: data)
        
        #expect(config.id == id)
        #expect(config.name == "Bedroom TV")
        #expect(config.ipAddress == "192.168.1.200")
        #expect(config.macAddress == "11:22:33:44:55:66")
        #expect(config.preferredInput == "HDMI_3")
        #expect(config.wakeWithMac == false)
        #expect(config.sleepWithMac == false)
        #expect(config.switchInputOnWake == true)
        #expect(config.enablePCMode == true)
    }
    
    @Test("round-trip encode/decode preserves data")
    func roundTripEncodeDecode() throws {
        let original = TVConfiguration(
            name: "Round Trip TV",
            ipAddress: "10.0.0.1",
            macAddress: "FF:EE:DD:CC:BB:AA",
            preferredInput: "HDMI_4",
            wakeWithMac: true,
            sleepWithMac: false,
            switchInputOnWake: true,
            enablePCMode: true
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(TVConfiguration.self, from: data)
        
        #expect(decoded.id == original.id)
        #expect(decoded.name == original.name)
        #expect(decoded.ipAddress == original.ipAddress)
        #expect(decoded.macAddress == original.macAddress)
        #expect(decoded.preferredInput == original.preferredInput)
        #expect(decoded.wakeWithMac == original.wakeWithMac)
        #expect(decoded.sleepWithMac == original.sleepWithMac)
        #expect(decoded.switchInputOnWake == original.switchInputOnWake)
        #expect(decoded.enablePCMode == original.enablePCMode)
    }
    
    // MARK: - Identifiable Tests
    
    @Test("conforms to Identifiable protocol")
    func conformsToIdentifiable() {
        let config = TVConfiguration(
            name: "Test TV",
            ipAddress: "192.168.1.1",
            macAddress: "AA:BB:CC:DD:EE:FF"
        )
        
        // Identifiable requires id property which we already have
        let _: UUID = config.id
    }
    
    @Test("two configurations with same id are considered same identity")
    func sameIdSameIdentity() {
        let id = UUID()
        let config1 = TVConfiguration(
            id: id,
            name: "TV 1",
            ipAddress: "192.168.1.1",
            macAddress: "AA:BB:CC:DD:EE:FF"
        )
        let config2 = TVConfiguration(
            id: id,
            name: "TV 2",
            ipAddress: "192.168.1.2",
            macAddress: "11:22:33:44:55:66"
        )
        
        #expect(config1.id == config2.id)
    }
    
    // MARK: - Edge Cases
    
    @Test("handles empty strings")
    func handlesEmptyStrings() {
        let config = TVConfiguration(
            name: "",
            ipAddress: "",
            macAddress: ""
        )
        
        #expect(config.name == "")
        #expect(config.ipAddress == "")
        #expect(config.macAddress == "")
    }
    
    @Test("handles special characters in name")
    func handlesSpecialCharactersInName() throws {
        let config = TVConfiguration(
            name: "TV \"Main\" 📺",
            ipAddress: "192.168.1.1",
            macAddress: "AA:BB:CC:DD:EE:FF"
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(config)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(TVConfiguration.self, from: data)
        
        #expect(decoded.name == "TV \"Main\" 📺")
    }
}
