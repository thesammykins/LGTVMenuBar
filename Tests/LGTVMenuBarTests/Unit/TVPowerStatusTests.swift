import Testing
@testable import LGTVMenuBar

@Suite("TVPowerStatus Tests")
struct TVPowerStatusTests {
    @Test("active state normalizes to active")
    func activeStateNormalizesToActive() {
        let status = TVPowerStatus(state: "Active")

        #expect(status.normalizedState == .active)
    }

    @Test("screen off state normalizes to screenOff")
    func screenOffStateNormalizesToScreenOff() {
        let status = TVPowerStatus(state: "Screen Off")

        #expect(status.normalizedState == .screenOff)
    }

    @Test("active standby normalizes to pixel refresher")
    func activeStandbyNormalizesToPixelRefresher() {
        let status = TVPowerStatus(state: "Active Standby")

        #expect(status.normalizedState == .pixelRefresher)
    }

    @Test("request suspend normalizes to turningOff")
    func requestSuspendNormalizesToTurningOff() {
        let status = TVPowerStatus(state: "Active", processing: "Request Suspend")

        #expect(status.normalizedState == .turningOff)
    }
}
