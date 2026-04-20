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

    @Test("sendCommand surfaces test send failures")
    func sendCommandSurfacesFailures() async {
        let client = WebOSClient(keychainManager: MockKeychainManager())
        client.setConnectionStateForTesting(.connected, handshakeCompleted: true)
        client.setTestSendCommandHandler { _ in
            throw MockWebOSClientError.commandFailed("send failed")
        }

        await #expect(throws: LGTVError.self) {
            try await client.sendCommand(.screenOn)
        }
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
