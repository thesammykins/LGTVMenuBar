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
}
