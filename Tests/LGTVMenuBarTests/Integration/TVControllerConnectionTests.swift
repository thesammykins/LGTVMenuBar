import Testing
import Foundation
@testable import LGTVMenuBar

@Suite("TV Controller Connection Tests")
@MainActor
struct TVControllerConnectionTests {
    @Test("duplicate connect joins in-flight pairing attempt")
    func duplicateConnectJoinsInFlightPairingAttempt() async throws {
        let mockWebOS = MockWebOSClient()
        let mockDiagnostic = MockDiagnosticLogger()
        mockWebOS.asyncDelay = 0.05

        let controller = TVController(
            webOSClient: mockWebOS,
            wolService: MockWOLService(),
            powerManager: MockPowerManager(),
            keychainManager: MockKeychainManager(),
            mediaKeyManager: MockMediaKeyManager(),
            launchAtLoginManager: MockLaunchAtLoginManager(),
            diagnosticLogger: mockDiagnostic
        )

        let config = TVConfiguration(
            name: "Test TV",
            ipAddress: "192.168.1.100",
            macAddress: "AA:BB:CC:DD:EE:FF"
        )
        try controller.saveConfiguration(config)

        let firstConnect = Task {
            try await controller.connect()
        }
        try await Task.sleep(for: .milliseconds(10))

        try await controller.connect()
        try await firstConnect.value

        #expect(mockWebOS.connectCallCount == 1)
        #expect(controller.connectionState == .connected)
        #expect(mockDiagnostic.wasLogged(message: "Joining in-flight TV connection"))
    }

    @Test("stale WebOS state callback is ignored after disconnect")
    func staleWebOSStateCallbackIsIgnoredAfterDisconnect() async throws {
        let mockWebOS = MockWebOSClient()

        let controller = TVController(
            webOSClient: mockWebOS,
            wolService: MockWOLService(),
            powerManager: MockPowerManager(),
            keychainManager: MockKeychainManager(),
            mediaKeyManager: MockMediaKeyManager(),
            launchAtLoginManager: MockLaunchAtLoginManager(),
            diagnosticLogger: MockDiagnosticLogger()
        )

        let config = TVConfiguration(
            name: "Test TV",
            ipAddress: "192.168.1.100",
            macAddress: "AA:BB:CC:DD:EE:FF"
        )
        try controller.saveConfiguration(config)
        try await controller.connect()

        controller.disconnect()
        mockWebOS.emitStaleConnectionStateCallback(.registering)
        await Task.yield()

        #expect(controller.connectionState == .disconnected)
    }
}
