import Testing
import Foundation
@testable import LGTVMenuBar

@Suite("WebOSClient Tests")
@MainActor
struct WebOSClientTests {

    @Test("registered message transitions client to connected state")
    func registeredMessageTransitionsToConnected() async {
        let client = WebOSClient(keychainManager: MockKeychainManager())
        var observedStates: [ConnectionState] = []
        client.setTestStateChangeObserver { state in
            observedStates.append(state)
        }
        client.setTestSendCommandHandler { _ in }

        client.setConnectionStateForTesting(.registering, handshakeCompleted: false)

        let registeredMessage = """
        {
          "type": "registered",
          "payload": {
            "client-key": "test-client-key"
          }
        }
        """

        await client.handleMessageForTesting(registeredMessage)

        #expect(observedStates.contains(.connected))
        #expect(client.connectionState == .connected)
    }

    @Test("sendCommand transport failure marks connection error")
    func sendCommandTransportFailureMarksConnectionError() async {
        let client = WebOSClient(keychainManager: MockKeychainManager())
        var observedStates: [ConnectionState] = []
        client.setTestStateChangeObserver { state in
            observedStates.append(state)
        }
        client.setConnectionStateForTesting(.connected, handshakeCompleted: true)
        client.setTestSendCommandHandler { _ in
            throw MockWebOSClientError.commandFailed("send failed")
        }

        await #expect(throws: LGTVError.self) {
            try await client.sendCommand(.screenOn)
        }
        #expect(client.connectionState.hasError)
        #expect(!client.connectionState.isConnected)
        #expect(observedStates.contains { $0.hasError })
    }

    @Test("getPowerStatus transport failure marks connection error")
    func getPowerStatusTransportFailureMarksConnectionError() async {
        let client = WebOSClient(keychainManager: MockKeychainManager())
        var observedStates: [ConnectionState] = []
        client.setTestStateChangeObserver { state in
            observedStates.append(state)
        }
        client.setConnectionStateForTesting(.connected, handshakeCompleted: true)
        client.setTestSendCommandHandler { command in
            if case .getPowerState = command {
                // Expected command for power status transport checks.
            } else {
                Issue.record("Expected getPowerState command")
            }
            throw MockWebOSClientError.connectionFailed("connection lost")
        }

        await #expect(throws: Error.self) {
            _ = try await client.getPowerStatus()
        }
        #expect(client.connectionState.hasError)
        #expect(!client.connectionState.isConnected)
        #expect(observedStates.contains { $0.hasError })
    }

    @Test("sendCommand rejects commands before handshake completion")
    func sendCommandRejectsBeforeHandshakeCompletion() async {
        let client = WebOSClient(keychainManager: MockKeychainManager())
        client.setConnectionStateForTesting(.registering, handshakeCompleted: false)

        await #expect(throws: LGTVError.self) {
            try await client.sendCommand(.screenOn)
        }
    }

    @Test("stale connection attempt state changes are ignored")
    func staleConnectionAttemptStateChangesAreIgnored() async {
        let client = WebOSClient(keychainManager: MockKeychainManager())
        var observedStates: [ConnectionState] = []
        client.setTestStateChangeObserver { state in
            observedStates.append(state)
        }

        let staleAttempt = client.beginConnectionAttemptForTesting()
        let currentAttempt = client.beginConnectionAttemptForTesting()

        client.emitConnectionStateForTesting(.registering, attemptID: staleAttempt)
        #expect(observedStates.isEmpty)
        #expect(client.connectionState == .disconnected)

        client.emitConnectionStateForTesting(.connecting, attemptID: currentAttempt)
        #expect(observedStates == [.connecting])
        #expect(client.connectionState == .connecting)
    }

    @Test("connect while registering does not restart pairing")
    func connectWhileRegisteringDoesNotRestartPairing() async throws {
        let client = WebOSClient(keychainManager: MockKeychainManager())
        var observedStates: [ConnectionState] = []
        client.setTestStateChangeObserver { state in
            observedStates.append(state)
        }
        client.setConnectionStateForTesting(.registering, handshakeCompleted: false)

        let config = TVConfiguration(
            name: "Test TV",
            ipAddress: "192.168.1.100",
            macAddress: "AA:BB:CC:DD:EE:FF"
        )

        try await client.connect(to: config) { _ in }

        #expect(client.connectionState == .registering)
        #expect(observedStates.isEmpty)
    }

    @Test("response payload handles nested foreground app info")
    func responsePayloadHandlesNestedForegroundAppInfo() async {
        let client = WebOSClient(keychainManager: MockKeychainManager())
        let recorder = WebOSPayloadRecorder()
        client.setInputChangeCallback { input in
            recorder.input = input
        }

        let message = """
        {
          "type": "response",
          "payload": {
            "foregroundAppInfo": {
              "appId": "com.webos.app.hdmi2"
            }
          }
        }
        """

        await client.handleMessageForTesting(message)

        #expect(recorder.input == .hdmi2)
    }

    @Test("response payload handles nested volume status")
    func responsePayloadHandlesNestedVolumeStatus() async {
        let client = WebOSClient(keychainManager: MockKeychainManager())
        let recorder = WebOSPayloadRecorder()
        client.setVolumeChangeCallback { volume, isMuted in
            recorder.volume = volume
            recorder.isMuted = isMuted
        }

        let message = """
        {
          "type": "response",
          "payload": {
            "volumeStatus": {
              "volume": 42,
              "muteStatus": true
            }
          }
        }
        """

        await client.handleMessageForTesting(message)

        #expect(recorder.volume == 42)
        #expect(recorder.isMuted == true)
    }

    @Test("response payload handles nested sound output")
    func responsePayloadHandlesNestedSoundOutput() async {
        let client = WebOSClient(keychainManager: MockKeychainManager())
        let recorder = WebOSPayloadRecorder()
        client.setSoundOutputChangeCallback { output in
            recorder.soundOutput = output
        }

        let message = """
        {
          "type": "response",
          "payload": {
            "soundOutput": {
              "output": "external_arc"
            }
          }
        }
        """

        await client.handleMessageForTesting(message)

        #expect(recorder.soundOutput == .externalArc)
    }
}

private final class WebOSPayloadRecorder: @unchecked Sendable {
    var input: TVInputType?
    var volume: Int?
    var isMuted: Bool?
    var soundOutput: TVSoundOutput?
}
