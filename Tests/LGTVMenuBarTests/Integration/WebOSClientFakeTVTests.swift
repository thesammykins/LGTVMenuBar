import Testing
import Foundation
@testable import LGTVMenuBar

/// Exercises the real client against a real WebSocket on loopback.
@Suite("WebOSClient against FakeTV", .serialized)
@MainActor
struct WebOSClientFakeTVTests {

    private final class StateRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var _states: [ConnectionState] = []
        func append(_ state: ConnectionState) { lock.lock(); _states.append(state); lock.unlock() }
        var states: [ConnectionState] { lock.lock(); defer { lock.unlock() }; return _states }
    }

    private let config = TVConfiguration(name: "Fake", ipAddress: "127.0.0.1", macAddress: "AA:BB:CC:DD:EE:FF")

    private func makeClient(
        _ tv: FakeTV,
        keychain: MockKeychainManager = MockKeychainManager(),
        endpointCount: Int = 1,
        handshake: Duration = .milliseconds(400),
        pairingPrompt: Duration = .seconds(5),
        reply: Duration = .milliseconds(400)
    ) -> WebOSClient {
        let endpoint = WebOSConnectionEndpoint(scheme: "ws", port: tv.port)
        return WebOSClient(
            keychainManager: keychain,
            endpoints: Array(repeating: endpoint, count: endpointCount),
            timeouts: .init(handshake: handshake, pairingPrompt: pairingPrompt, reply: reply, keepAliveInterval: .seconds(600))
        )
    }

    private func waitUntil(timeout: Duration = .seconds(5), _ condition: @MainActor () -> Bool) async {
        let deadline = ContinuousClock.now + timeout
        while !condition() && ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test("registers, stores the client key and learns the TV's state")
    func registersAndBootstraps() async throws {
        let tv = FakeTV()
        try await tv.start()
        defer { tv.stop() }
        tv.setReply(["appId": "com.webos.app.hdmi2"], for: "ssap://com.webos.applicationManager/getForegroundAppInfo")
        tv.setReply(["devices": [["id": "HDMI_1", "label": "PC", "icon": "pc.png", "connected": true], ["id": "HDMI_2", "label": "HDMI 2", "icon": "hdmi.png", "connected": false]]], for: "ssap://tv/getExternalInputList")
        tv.setReply(["modelName": "OLED42C24LA"], for: "ssap://system/getSystemInfo")

        let keychain = MockKeychainManager()
        let client = makeClient(tv, keychain: keychain)
        nonisolated(unsafe) var foreground: TVForeground?
        nonisolated(unsafe) var capabilities: TVCapabilities?
        client.setForegroundChangeCallback { foreground = $0 }
        client.setCapabilityCallback { capabilities = $0 }

        try await client.connect(to: config) { _ in }
        #expect(client.connectionState == .connected)
        #expect(try keychain.loadClientKey(for: "127.0.0.1") == "fake-client-key")

        await waitUntil { capabilities?.displayModel == "OLED42C24LA" }
        #expect(foreground == .input(.hdmi2))
        #expect(capabilities?.inputs.map(\.id) == ["HDMI_1", "HDMI_2"])
        #expect(capabilities?.inputs.first?.isPCMode == true)
        client.disconnect()
    }

    @Test("a TV that accepts the socket but never answers fails within the handshake timeout")
    func silentTVTimesOut() async throws {
        let tv = FakeTV()
        try await tv.start()
        defer { tv.stop() }
        tv.registration = .silent
        let client = makeClient(tv)

        let started = ContinuousClock.now
        await #expect(throws: LGTVError.self) {
            try await client.connect(to: config) { _ in }
        }
        #expect(ContinuousClock.now - started < .seconds(3))
        #expect(client.connectionState == .disconnected)

        // The client is usable again straight away.
        tv.registration = .accept
        try await client.connect(to: config) { _ in }
        #expect(client.connectionState == .connected)
        client.disconnect()
    }

    @Test("a pairing prompt accepted after the handshake timeout still connects")
    func slowPairingSucceeds() async throws {
        let tv = FakeTV()
        try await tv.start()
        defer { tv.stop() }
        tv.registration = .promptThenAccept(after: 1.0)
        let client = makeClient(tv, handshake: .milliseconds(300))
        let recorder = StateRecorder()

        try await client.connect(to: config) { recorder.append($0) }

        #expect(client.connectionState == .connected)
        #expect(recorder.states.contains(.awaitingPairing))
        #expect(tv.registerCount == 1)
        client.disconnect()
    }

    @Test("an unanswered pairing prompt ends as a pairing timeout without a second prompt")
    func unansweredPromptTimesOut() async throws {
        let tv = FakeTV()
        try await tv.start()
        defer { tv.stop() }
        tv.registration = .promptOnly
        let client = makeClient(tv, endpointCount: 2, pairingPrompt: .milliseconds(500))

        await #expect(throws: LGTVError.pairingTimeout) {
            try await client.connect(to: config) { _ in }
        }
        #expect(tv.registerCount == 1)
        #expect(client.connectionState == .disconnected)
    }

    @Test("a refused pairing is reported as rejected and not retried on the next endpoint")
    func rejectedPairing() async throws {
        let tv = FakeTV()
        try await tv.start()
        defer { tv.stop() }
        tv.registration = .reject
        let client = makeClient(tv, endpointCount: 2)

        await #expect(throws: LGTVError.pairingRejected) {
            try await client.connect(to: config) { _ in }
        }
        #expect(tv.registerCount == 1)
    }

    @Test("disconnect during connect stops the attempt instead of trying the next endpoint")
    func disconnectCancelsConnect() async throws {
        let tv = FakeTV()
        try await tv.start()
        defer { tv.stop() }
        tv.registration = .silent
        let client = makeClient(tv, endpointCount: 2, handshake: .seconds(30))

        let connectTask = Task { @MainActor in
            try await client.connect(to: config) { _ in }
        }
        await waitUntil { tv.registerCount == 1 }
        client.disconnect()

        await #expect(throws: LGTVError.self) { try await connectTask.value }
        try await Task.sleep(for: .milliseconds(200))
        #expect(tv.registerCount == 1)
        #expect(client.connectionState == .disconnected)
    }

    @Test("a command the TV rejects throws instead of reporting success")
    func rejectedCommandThrows() async throws {
        let tv = FakeTV()
        try await tv.start()
        defer { tv.stop() }
        tv.setReply(["returnValue": false, "errorCode": "-1000", "errorText": "no such input"], for: "ssap://tv/switchInput")
        let client = makeClient(tv)
        try await client.connect(to: config) { _ in }

        do {
            try await client.sendCommand(.setInput("HDMI_9"))
            Issue.record("expected the command to throw")
        } catch let error as LGTVError {
            guard case .commandFailed(let message) = error else {
                Issue.record("unexpected error \(error)")
                return
            }
            #expect(message.contains("no such input"))
        }
        #expect(client.connectionState == .connected)
        client.disconnect()
    }

    @Test("a command the TV never answers times out and leaves the connection up")
    func unansweredCommandTimesOut() async throws {
        let tv = FakeTV()
        try await tv.start()
        defer { tv.stop() }
        tv.setSilent("ssap://audio/setVolume")
        let client = makeClient(tv)
        try await client.connect(to: config) { _ in }

        await #expect(throws: LGTVError.requestTimedOut("ssap://audio/setVolume")) {
            try await client.sendCommand(.setVolume(10))
        }
        #expect(client.connectionState == .connected)
        client.disconnect()
    }

    @Test("power off counts as sent when the TV goes quiet")
    func powerOffToleratesSilence() async throws {
        let tv = FakeTV()
        try await tv.start()
        defer { tv.stop() }
        tv.setSilent("ssap://system/turnOff")
        let client = makeClient(tv)
        try await client.connect(to: config) { _ in }

        try await client.sendCommand(.powerOff)
        #expect(tv.requestCount(for: "ssap://system/turnOff") == 1)
        client.disconnect()
    }

    @Test("mute falls back to the legacy endpoint when setMute is rejected")
    func muteFallback() async throws {
        let tv = FakeTV()
        try await tv.start()
        defer { tv.stop() }
        tv.setReply(["returnValue": false, "errorText": "unknown method"], for: "ssap://audio/setMute")
        let client = makeClient(tv)
        try await client.connect(to: config) { _ in }

        try await client.sendCommand(.mute)
        #expect(tv.requestCount(for: "ssap://audio/mute") == 1)
        client.disconnect()
    }

    @Test("the input list falls back to its older endpoint name")
    func inputListFallback() async throws {
        let tv = FakeTV()
        try await tv.start()
        defer { tv.stop() }
        tv.setReply(["returnValue": false, "errorText": "404 no such service or method"], for: "ssap://tv/getExternalInputList")
        tv.setReply(["devices": [["id": "HDMI_1", "label": "PC", "icon": "pc.png", "connected": true]]], for: "ssap://tv/getInputList")
        let client = makeClient(tv)
        nonisolated(unsafe) var icons: [String: String] = [:]
        client.setInputListCallback { icons = $0 }
        try await client.connect(to: config) { _ in }

        await waitUntil { !icons.isEmpty }
        #expect(icons == ["HDMI_1": "pc.png"])
        client.disconnect()
    }

    @Test("a dropped socket moves the client to the error state and fails waiting requests")
    func dropIsDetected() async throws {
        let tv = FakeTV()
        try await tv.start()
        defer { tv.stop() }
        tv.setSilent("ssap://audio/setVolume")
        let client = makeClient(tv, reply: .seconds(20))
        try await client.connect(to: config) { _ in }

        let pending = Task { @MainActor in try await client.sendCommand(.setVolume(5)) }
        await waitUntil { tv.requestCount(for: "ssap://audio/setVolume") == 1 }
        tv.dropConnections()

        await #expect(throws: (any Error).self) { try await pending.value }
        await waitUntil { client.connectionState.hasError }
        #expect(client.connectionState.hasError)
    }

    @Test("subscription updates report apps as apps, not as the last input")
    func foregroundUpdates() async throws {
        let tv = FakeTV()
        try await tv.start()
        defer { tv.stop() }
        let uri = "ssap://com.webos.applicationManager/getForegroundAppInfo"
        tv.setReply(["appId": "com.webos.app.hdmi1"], for: uri)
        let client = makeClient(tv)
        nonisolated(unsafe) var foreground: TVForeground?
        client.setForegroundChangeCallback { foreground = $0 }
        try await client.connect(to: config) { _ in }
        await waitUntil { foreground == .input(.hdmi1) }

        tv.push(["appId": "netflix"], for: uri)
        await waitUntil { foreground == .app("netflix") }
        #expect(foreground == .app("netflix"))

        tv.push(["appId": ""], for: uri)
        try await Task.sleep(for: .milliseconds(100))
        #expect(foreground == .app("netflix"))
        client.disconnect()
    }

    @Test("an idle connection that stops answering is detected by the keep-alive")
    func keepAliveDetectsDeadPeer() async throws {
        let tv = FakeTV()
        try await tv.start()
        defer { tv.stop() }
        let endpoint = WebOSConnectionEndpoint(scheme: "ws", port: tv.port)
        let client = WebOSClient(
            keychainManager: MockKeychainManager(),
            endpoints: [endpoint],
            timeouts: .init(handshake: .seconds(1), pairingPrompt: .seconds(1), reply: .milliseconds(300), keepAliveInterval: .milliseconds(300))
        )
        try await client.connect(to: config) { _ in }
        try await Task.sleep(for: .milliseconds(500))
        #expect(client.connectionState == .connected)

        tv.setSilent("ssap://audio/getVolume")
        await waitUntil { client.connectionState.hasError }
        #expect(client.connectionState.hasError)
    }
}
