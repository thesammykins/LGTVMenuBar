import Foundation

/// Pure decisions about making room for the TV's pixel refresh. Every rule has a test.
public enum PanelCarePolicy {
    /// How long a refresh the app made room for is left undisturbed. A short refresh takes
    /// around five to seven minutes.
    public static let maximumRefreshWindow: TimeInterval = 600

    /// Keyboard or mouse input this recent means someone is at the Mac.
    public static let presenceThreshold: TimeInterval = 30

    public enum PowerOffDecision: Equatable, Sendable {
        case powerOff
        case leaveOn(reason: String)
    }

    /// Whether to switch the TV off so a due refresh can run.
    ///
    /// Only ever while the Mac is locked (or asleep, which the sleep path handles): a refresh
    /// must never take the display away from someone using the Mac. The set hours can only
    /// narrow that further.
    public static func powerOffDecision(
        isEnabled: Bool,
        isMacLocked: Bool,
        isWithinAllowedHours: Bool,
        status: PanelCareStatus?,
        isConnected: Bool,
        foreground: TVForeground,
        preferredInput: String
    ) -> PowerOffDecision {
        guard isEnabled else { return .leaveOn(reason: "panel care is off") }
        guard isMacLocked else { return .leaveOn(reason: "the Mac is not locked") }
        guard isWithinAllowedHours else { return .leaveOn(reason: "outside the set hours") }
        guard isConnected else { return .leaveOn(reason: "not connected to the TV") }
        guard let status else { return .leaveOn(reason: "panel-care state is not available") }
        guard status.isRefreshDue else { return .leaveOn(reason: "no refresh is due") }

        switch foreground {
        case .input(let input) where input.rawValue == preferredInput:
            return .powerOff
        case .input(let input):
            return .leaveOn(reason: "TV is on \(input.displayName)")
        case .app:
            return .leaveOn(reason: "TV is showing an app")
        case .unknown:
            // Unlike Mac sleep, there is no cost to waiting for the next chance.
            return .leaveOn(reason: "what the TV is showing is not known")
        }
    }

    public enum WakeDecision: Equatable, Sendable {
        case proceed
        case hold
    }

    /// Whether a wake trigger may interrupt a refresh in progress.
    ///
    /// Someone at the Mac always gets their display back: unlocking, opening the menu and
    /// recent input all proceed. A wake with nobody there (a scheduled or network wake) waits,
    /// because those are what leave a monitor's refresh permanently overdue.
    public static func wakeDecision(trigger: PowerPolicy.Trigger, userIdleSeconds: TimeInterval) -> WakeDecision {
        switch trigger {
        case .screenUnlock, .menuOpened, .appActivated, .userRequested:
            return .proceed
        case .systemWake, .screenWake:
            return userIdleSeconds < presenceThreshold ? .proceed : .hold
        }
    }
}
