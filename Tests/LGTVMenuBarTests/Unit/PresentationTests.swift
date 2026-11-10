import Testing
import Foundation
@testable import LGTVMenuBar

@Suite("InputValidation")
struct InputValidationTests {
    @Test("hosts: IPv4 addresses and host names pass, malformed values explain why", arguments: [
        ("192.168.1.20", true), ("10.0.0.1", true), ("lgtv.local", true), ("tv-lounge", true),
        ("", false), ("192.168.1", false), ("192.168.1.256", false), ("192.168..1", false),
        ("tv lounge", false), ("-tv", false), ("192.168.1.20:3001", false)
    ])
    func host(value: String, isValid: Bool) {
        #expect((InputValidation.host(value) == nil) == isValid)
    }

    @Test("an empty optional host is fine")
    func optionalHost() {
        #expect(InputValidation.optionalHost("") == nil)
        #expect(InputValidation.optionalHost("999.1.1.1") != nil)
    }

    @Test("MAC addresses accept common separators and are normalised", arguments: [
        ("AA:BB:CC:DD:EE:FF", true), ("aa-bb-cc-dd-ee-ff", true), ("aabbccddeeff", true),
        ("AA:BB:CC:DD:EE", false), ("AA:BB:CC:DD:EE:GG", false), ("AA.BB.CC.DD.EE.FF", false), ("", false)
    ])
    func macAddress(value: String, isValid: Bool) {
        #expect((InputValidation.macAddress(value) == nil) == isValid)
    }

    @Test("normalisation produces upper-case colon form")
    func normalizedMAC() {
        #expect(InputValidation.normalizedMACAddress("aa-bb-cc-dd-ee-ff") == "AA:BB:CC:DD:EE:FF")
        #expect(InputValidation.normalizedMACAddress("aabbccddeeff") == "AA:BB:CC:DD:EE:FF")
        #expect(InputValidation.normalizedMACAddress("nonsense") == "nonsense")
    }

    @Test("ports and durations are optional but bounded")
    func numbers() {
        #expect(InputValidation.optionalPort("") == nil)
        #expect(InputValidation.optionalPort("9") == nil)
        #expect(InputValidation.optionalPort("0") != nil)
        #expect(InputValidation.optionalPort("70000") != nil)
        #expect(InputValidation.optionalPort("ssh") != nil)
        #expect(InputValidation.optionalSeconds("", range: 10...600) == nil)
        #expect(InputValidation.optionalSeconds("90", range: 10...600) == nil)
        #expect(InputValidation.optionalSeconds("5", range: 10...600) != nil)
    }
}

@Suite("ConnectionPresentation")
struct ConnectionPresentationTests {
    private func make(_ state: ConnectionState, name: String? = "LG C2", foreground: TVForeground = .unknown, pairing: Bool = false) -> ConnectionPresentation {
        ConnectionPresentation.make(state: state, tvName: name, foreground: foreground, pairingRequiresUser: pairing)
    }

    @Test("no TV points the user at Settings")
    func noTV() {
        let presentation = make(.disconnected, name: nil)
        #expect(presentation.title == "No TV set up")
        #expect(presentation.detail == "Add your TV in Settings.")
    }

    @Test("connected says what the TV is showing")
    func connected() {
        #expect(make(.connected, foreground: .input(.hdmi2)).detail == "On HDMI 2")
        #expect(make(.connected, foreground: .app("netflix")).detail == "Showing a TV app")
        #expect(make(.connected).detail == "Connected")
        #expect(make(.connected).tone == .good)
    }

    @Test("in-progress states show progress and say what is needed")
    func inProgress() {
        #expect(make(.connecting).showsProgress)
        #expect(make(.registering).showsProgress)
        #expect(make(.awaitingPairing).detail == "Accept the prompt on your TV")
    }

    @Test("an error carries its reason")
    func error() {
        let presentation = make(.error(LGTVError.connectionFailed("The TV stopped responding")))
        #expect(presentation.detail == "Connection lost: Connection failed: The TV stopped responding")
        #expect(presentation.tone == .problem)
    }

    @Test("a refused pairing tells the user what to do")
    func pairingNeeded() {
        let presentation = make(.disconnected, pairing: true)
        #expect(presentation.detail?.contains("Pairing needed") == true)
        #expect(presentation.tone == .problem)
    }

    @Test("every state has a different symbol from 'connected', so status is not colour-only")
    func symbolsDiffer() {
        let connected = make(.connected).symbolName
        for state in [ConnectionState.disconnected, .connecting, .awaitingPairing, .error(LGTVError.tvNotFound)] {
            #expect(make(state).symbolName != connected)
        }
    }
}
