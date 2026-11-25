import Foundation

/// Whether the Mac's displays have settled after a wake or a reconfiguration.
///
/// Writing a display mode, HDR or the TV's PC label while an HDMI link is still training starts
/// another handshake, and on a link that is failing to train that keeps it failing. So nothing
/// is written until the displays have been quiet for `settleInterval`, and a run of
/// reconfigurations is treated as a storm that needs a longer quiet before anything is tried.
public struct DisplayStability: Equatable, Sendable {
    /// Quiet time after a wake or reconfiguration before anything is written to the display.
    public static let settleInterval: TimeInterval = 30
    /// Reconfigurations within this span of each other count toward a storm, and a storm ends
    /// after this long without one.
    public static let stormWindow: TimeInterval = 60
    public static let stormThreshold = 3
    /// macOS posts several notifications for one change; ones this close are one reconfiguration.
    public static let burstInterval: TimeInterval = 1

    public enum State: Equatable, Sendable {
        case stable
        case settling(until: Date)
        case storm(reconfigurations: Int, until: Date)

        public var isStable: Bool { self == .stable }

        public var isStorm: Bool {
            if case .storm = self { return true }
            return false
        }

        public var until: Date? {
            switch self {
            case .stable: return nil
            case .settling(let until), .storm(_, let until): return until
            }
        }
    }

    private var lastEvent: Date?
    private var lastNotification: Date?
    /// The start of each reconfiguration within `stormWindow` of the latest one.
    private var reconfigurations: [Date] = []

    public init() {}

    public mutating func noteWake(at date: Date) {
        lastEvent = date
    }

    public mutating func noteReconfiguration(at date: Date) {
        defer {
            lastNotification = date
            lastEvent = date
        }
        if let lastNotification, date.timeIntervalSince(lastNotification) < Self.burstInterval { return }
        reconfigurations.removeAll { date.timeIntervalSince($0) > Self.stormWindow }
        reconfigurations.append(date)
    }

    public func state(at now: Date) -> State {
        guard let lastEvent else { return .stable }
        if reconfigurations.count >= Self.stormThreshold {
            let until = lastEvent.addingTimeInterval(Self.stormWindow)
            if now < until { return .storm(reconfigurations: reconfigurations.count, until: until) }
        }
        let until = lastEvent.addingTimeInterval(Self.settleInterval)
        return now < until ? .settling(until: until) : .stable
    }
}
