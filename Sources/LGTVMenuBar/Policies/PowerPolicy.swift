import Foundation

/// Pure decisions for the power and input automation. Every rule here has a test.
public enum PowerPolicy {

    /// Why automation is being asked to act.
    public enum Trigger: String, Sendable {
        case systemWake
        case screenWake
        case screenUnlock
        case menuOpened
        case appActivated
        case userRequested
    }

    public enum TriggerDecision: Equatable, Sendable {
        /// Make sure the TV is powered and its screen is on.
        case wake
        /// Connect if the TV is already reachable; never power it on.
        case reconnectOnly
        case nothing
    }

    public static func decision(for trigger: Trigger, config: TVConfiguration, isConnected: Bool) -> TriggerDecision {
        switch trigger {
        case .userRequested:
            return .wake
        case .systemWake, .screenWake, .screenUnlock:
            if config.wakeWithMac { return .wake }
            return isConnected ? .nothing : .reconnectOnly
        case .menuOpened:
            if config.wakeWithMac && config.wakeOnMenuOpen { return .wake }
            return isConnected ? .nothing : .reconnectOnly
        case .appActivated:
            // Opening Settings or any app window must not power on a TV.
            return isConnected ? .nothing : .reconnectOnly
        }
    }

    public enum SleepDecision: Equatable, Sendable {
        case powerOff
        case leaveOn(reason: String)
        case skip(reason: String)
    }

    /// The TV is only powered off when the Mac's own input is in front. Anything else means
    /// someone is watching something that has nothing to do with the Mac.
    public static func sleepDecision(config: TVConfiguration, isConnected: Bool, foreground: TVForeground) -> SleepDecision {
        guard config.sleepWithMac else { return .skip(reason: "sleep automation disabled") }
        guard isConnected else { return .skip(reason: "not connected to the TV") }

        switch foreground {
        case .input(let input):
            if input.rawValue == config.preferredInput { return .powerOff }
            return .leaveOn(reason: "TV is on \(input.displayName)")
        case .app(let appId):
            return .leaveOn(reason: "TV is showing \(appId)")
        case .unknown:
            // Nothing says the TV is in use for something else, and leaving a display on all
            // night is the worse failure for a Mac monitor.
            return .powerOff
        }
    }

    public struct PostWakeActions: Equatable, Sendable {
        public var switchInput: Bool
        public var setPCMode: Bool

        public init(switchInput: Bool, setPCMode: Bool) {
            self.switchInput = switchInput
            self.setPCMode = setPCMode
        }

        public static let none = PostWakeActions(switchInput: false, setPCMode: false)
    }

    /// What to do once this app has turned the TV on. A TV found already on never gets here:
    /// its input is someone's choice and is left alone.
    public static func postWakeActions(
        config: TVConfiguration,
        foreground: TVForeground,
        preferredInputIsPCMode: Bool
    ) -> PostWakeActions {
        guard TVInputType(rawValue: config.preferredInput) != nil else { return .none }

        let onPreferredInput = foreground.input?.rawValue == config.preferredInput
        let switchInput = config.switchInputOnWake && !onPreferredInput
        // The PC label is written to the preferred input by id, so it does not disturb whatever
        // else the TV is showing.
        let setPCMode = config.enablePCMode && !preferredInputIsPCMode

        return PostWakeActions(switchInput: switchInput, setPCMode: setPCMode)
    }
}
