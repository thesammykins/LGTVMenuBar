import Testing
import Foundation
@testable import LGTVMenuBar

@Suite("TV Controller Volume Synchronization Tests")
@MainActor
struct TVControllerVolumeSynchronizationTests {

    private func waitUntil(
        timeout: Duration = .seconds(1),
        pollInterval: Duration = .milliseconds(10),
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        let deadline = ContinuousClock.now + timeout
        while !condition() && ContinuousClock.now < deadline {
            try? await Task.sleep(for: pollInterval)
        }
    }

    private func makeController() -> (TVController, MockWebOSClient, MockDiagnosticLogger) {
        let mockPowerManager = MockPowerManager()
        let mockWebOS = MockWebOSClient()
        let mockWOL = MockWOLService()
        let mockKeychain = MockKeychainManager()
        let mockMediaKey = MockMediaKeyManager()
        let mockLaunch = MockLaunchAtLoginManager()
        let mockDiagnostic = MockDiagnosticLogger()

        let controller = TVController(
            webOSClient: mockWebOS,
            wolService: mockWOL,
            powerManager: mockPowerManager,
            keychainManager: mockKeychain,
            mediaKeyManager: mockMediaKey,
            launchAtLoginManager: mockLaunch,
            diagnosticLogger: mockDiagnostic
        )

        #if LOCAL_ARYLIC_BUILD
        controller.isArylicVolumeControlEnabled = false
        controller.volumeControlTarget = .tv
        controller.arylicSettings = nil
        #endif

        return (controller, mockWebOS, mockDiagnostic)
    }

    @Test("setVolume ignores absolute level changes on HDMI ARC output")
    func setVolumeIgnoresAbsoluteLevelChangesOnExternalArc() async throws {
        let (controller, mockWebOS, mockDiagnostic) = makeController()

        mockWebOS.simulateSoundOutputChange(.externalArc)
        await waitUntil {
            controller.soundOutput == .externalArc
        }

        try await controller.setVolume(70)

        let setVolumeCalls = mockWebOS.sendCommandCalls.filter {
            if case .setVolume = $0.command { return true }
            return false
        }

        #expect(setVolumeCalls.isEmpty)
        #expect(controller.volume == 0)
        #expect(mockDiagnostic.wasLogged(message: "Ignored absolute volume set for unsupported sound output"))
    }

    @Test("setVolume sends absolute level changes for TV speaker output")
    func setVolumeSendsAbsoluteLevelChangesForTVSpeaker() async throws {
        let (controller, mockWebOS, _) = makeController()

        mockWebOS.simulateSoundOutputChange(.tvSpeaker)
        await waitUntil {
            controller.soundOutput == .tvSpeaker
        }

        try await controller.setVolume(42)

        let setVolumeValues = mockWebOS.sendCommandCalls.compactMap { call -> Int? in
            if case .setVolume(let level) = call.command {
                return level
            }
            return nil
        }

        #expect(setVolumeValues == [42])
        #expect(controller.volume == 42)
    }

    @Test("ARC output still follows callback updates while absolute sets are blocked")
    func externalArcVolumeStillFollowsCallbackUpdates() async throws {
        let (controller, mockWebOS, _) = makeController()

        mockWebOS.simulateSoundOutputChange(.externalArc)
        await waitUntil {
            controller.soundOutput == .externalArc
        }

        mockWebOS.simulateVolumeChange(volume: 60, isMuted: false)
        await waitUntil {
            controller.volume == 60 && controller.isMuted == false
        }

        try await controller.setVolume(90)

        mockWebOS.simulateVolumeChange(volume: 55, isMuted: true)
        await waitUntil {
            controller.volume == 55 && controller.isMuted == true
        }

        let setVolumeCalls = mockWebOS.sendCommandCalls.filter {
            if case .setVolume = $0.command { return true }
            return false
        }

        #expect(setVolumeCalls.isEmpty)
        #expect(controller.volume == 55)
        #expect(controller.isMuted == true)
    }
}
