import Foundation

/// Budget for automatic actions that change the TV or the Mac's display.
///
/// Automation reacts to events that its own actions can cause (a wake that drops the connection,
/// a mode change that renegotiates HDMI). Without a budget, a bad interaction becomes a loop that
/// power-cycles the TV or flips inputs indefinitely. Each kind of action gets a sliding window;
/// exceeding it trips that kind until a cooldown passes or the user resets it. Actions the user
/// asks for directly are never routed through the governor.
public struct ActionGovernor: Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        case powerOn
        case powerOff
        case inputSwitch
        case tvSettingWrite
        case displayModeChange

        public var displayName: String {
            switch self {
            case .powerOn: return "Automatic wake"
            case .powerOff: return "Automatic power off"
            case .inputSwitch: return "Automatic input switching"
            case .tvSettingWrite: return "Automatic TV setting changes"
            case .displayModeChange: return "Automatic display mode changes"
            }
        }
    }

    public struct Limit: Equatable, Sendable {
        public let maxActions: Int
        public let window: TimeInterval
        public let cooldown: TimeInterval

        public init(maxActions: Int, window: TimeInterval, cooldown: TimeInterval) {
            self.maxActions = max(1, maxActions)
            self.window = window
            self.cooldown = cooldown
        }

        /// Six in ten minutes is far above normal use (a handful of sleeps and wakes per hour)
        /// and far below what a loop produces.
        public static let standard = Limit(maxActions: 6, window: 600, cooldown: 900)
    }

    public enum Decision: Equatable, Sendable {
        case allowed
        case tripped(until: Date)

        public var isAllowed: Bool { self == .allowed }
    }

    private let limits: [Kind: Limit]
    private var history: [Kind: [Date]] = [:]
    private var trippedUntil: [Kind: Date] = [:]

    public init(limits: [Kind: Limit] = [:]) {
        self.limits = limits
    }

    private func limit(for kind: Kind) -> Limit {
        limits[kind] ?? .standard
    }

    /// Records an intended action and says whether it may run.
    public mutating func request(_ kind: Kind, now: Date = Date()) -> Decision {
        if let until = trippedUntil[kind] {
            if now < until {
                return .tripped(until: until)
            }
            trippedUntil[kind] = nil
            history[kind] = []
        }

        let limit = limit(for: kind)
        var recent = (history[kind] ?? []).filter { now.timeIntervalSince($0) < limit.window }

        if recent.count >= limit.maxActions {
            let until = now.addingTimeInterval(limit.cooldown)
            trippedUntil[kind] = until
            history[kind] = recent
            return .tripped(until: until)
        }

        recent.append(now)
        history[kind] = recent
        return .allowed
    }

    public func trippedKinds(now: Date = Date()) -> [Kind] {
        Kind.allCases.filter { kind in
            guard let until = trippedUntil[kind] else { return false }
            return now < until
        }
    }

    /// Clears one kind, or everything when `kind` is nil.
    public mutating func reset(_ kind: Kind? = nil) {
        if let kind {
            trippedUntil[kind] = nil
            history[kind] = nil
        } else {
            trippedUntil.removeAll()
            history.removeAll()
        }
    }
}
