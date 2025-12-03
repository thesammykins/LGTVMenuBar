import Testing
@testable import LGTVMenuBar

@Suite("TVInputType Tests")
struct TVInputTypeTests {
    
    // MARK: - rawValue Tests
    
    @Test("rawValue returns correct format for HDMI inputs")
    func rawValueHDMI() {
        #expect(TVInputType.hdmi1.rawValue == "HDMI_1")
        #expect(TVInputType.hdmi2.rawValue == "HDMI_2")
        #expect(TVInputType.hdmi3.rawValue == "HDMI_3")
        #expect(TVInputType.hdmi4.rawValue == "HDMI_4")
    }
    
    @Test("rawValue returns correct format for DisplayPort inputs")
    func rawValueDisplayPort() {
        #expect(TVInputType.displayPort1.rawValue == "DP_1")
        #expect(TVInputType.displayPort2.rawValue == "DP_2")
    }
    
    @Test("rawValue returns correct format for USB-C inputs")
    func rawValueUSBC() {
        #expect(TVInputType.usbC1.rawValue == "USBC_1")
        #expect(TVInputType.usbC2.rawValue == "USBC_2")
    }
    
    // MARK: - appId Tests
    
    @Test("appId returns correct WebOS app identifier for HDMI")
    func appIdHDMI() {
        #expect(TVInputType.hdmi1.appId == "com.webos.app.hdmi1")
        #expect(TVInputType.hdmi2.appId == "com.webos.app.hdmi2")
        #expect(TVInputType.hdmi3.appId == "com.webos.app.hdmi3")
        #expect(TVInputType.hdmi4.appId == "com.webos.app.hdmi4")
    }
    
    @Test("appId returns correct WebOS app identifier for DisplayPort")
    func appIdDisplayPort() {
        #expect(TVInputType.displayPort1.appId == "com.webos.app.dp1")
        #expect(TVInputType.displayPort2.appId == "com.webos.app.dp2")
    }
    
    @Test("appId returns correct WebOS app identifier for USB-C")
    func appIdUSBC() {
        #expect(TVInputType.usbC1.appId == "com.webos.app.usbc1")
        #expect(TVInputType.usbC2.appId == "com.webos.app.usbc2")
    }
    
    // MARK: - displayName Tests
    
    @Test("displayName returns human-readable names for HDMI")
    func displayNameHDMI() {
        #expect(TVInputType.hdmi1.displayName == "HDMI 1")
        #expect(TVInputType.hdmi2.displayName == "HDMI 2")
        #expect(TVInputType.hdmi3.displayName == "HDMI 3")
        #expect(TVInputType.hdmi4.displayName == "HDMI 4")
    }
    
    @Test("displayName returns human-readable names for DisplayPort")
    func displayNameDisplayPort() {
        #expect(TVInputType.displayPort1.displayName == "DisplayPort 1")
        #expect(TVInputType.displayPort2.displayName == "DisplayPort 2")
    }
    
    @Test("displayName returns human-readable names for USB-C")
    func displayNameUSBC() {
        #expect(TVInputType.usbC1.displayName == "USB-C 1")
        #expect(TVInputType.usbC2.displayName == "USB-C 2")
    }
    
    // MARK: - CaseIterable Tests
    
    @Test("allCases contains all 8 input types")
    func allCasesCount() {
        #expect(TVInputType.allCases.count == 8)
    }
    
    @Test("allCases contains expected types")
    func allCasesContents() {
        let cases = TVInputType.allCases
        #expect(cases.contains(.hdmi1))
        #expect(cases.contains(.hdmi2))
        #expect(cases.contains(.hdmi3))
        #expect(cases.contains(.hdmi4))
        #expect(cases.contains(.displayPort1))
        #expect(cases.contains(.displayPort2))
        #expect(cases.contains(.usbC1))
        #expect(cases.contains(.usbC2))
    }
    
    // MARK: - Init from rawValue Tests
    
    @Test("init from rawValue works for valid HDMI values")
    func initFromRawValueHDMI() {
        #expect(TVInputType(rawValue: "HDMI_1") == .hdmi1)
        #expect(TVInputType(rawValue: "HDMI_2") == .hdmi2)
        #expect(TVInputType(rawValue: "HDMI_3") == .hdmi3)
        #expect(TVInputType(rawValue: "HDMI_4") == .hdmi4)
    }
    
    @Test("init from rawValue works for valid DisplayPort values")
    func initFromRawValueDisplayPort() {
        #expect(TVInputType(rawValue: "DP_1") == .displayPort1)
        #expect(TVInputType(rawValue: "DP_2") == .displayPort2)
    }
    
    @Test("init from rawValue works for valid USB-C values")
    func initFromRawValueUSBC() {
        #expect(TVInputType(rawValue: "USBC_1") == .usbC1)
        #expect(TVInputType(rawValue: "USBC_2") == .usbC2)
    }
    
    @Test("init from rawValue returns nil for invalid values")
    func initFromRawValueInvalid() {
        #expect(TVInputType(rawValue: "INVALID") == nil)
        #expect(TVInputType(rawValue: "hdmi_1") == nil)  // lowercase
        #expect(TVInputType(rawValue: "HDMI1") == nil)   // missing underscore
        #expect(TVInputType(rawValue: "") == nil)
    }
}
