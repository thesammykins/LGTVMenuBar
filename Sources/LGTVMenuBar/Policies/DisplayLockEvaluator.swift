import Foundation

/// One thing Display Lock would change to bring the setup back to the profile.
public enum DisplayLockCorrection: Hashable, Sendable {
    case displayMode(DisplayModeSpec)
    case hdr(Bool)
    case pcMode
    case pictureMode(String)

    public var governorKind: ActionGovernor.Kind {
        switch self {
        case .displayMode, .hdr: return .displayModeChange
        case .pcMode, .pictureMode: return .tvSettingWrite
        }
    }

    public var label: String {
        switch self {
        case .displayMode(let mode): return "display mode \(mode.displayName)"
        case .hdr(let enabled): return enabled ? "HDR on" : "HDR off"
        case .pcMode: return "PC input label"
        case .pictureMode(let mode): return "picture mode \(mode)"
        }
    }
}

/// Everything the evaluation looks at, captured at one moment.
public struct DisplayLockSnapshot: Equatable, Sendable {
    public var isConnected: Bool
    public var foreground: TVForeground
    public var preferredInput: String
    public var display: DisplayInfo?
    /// Nil when not known; an unknown value is never "corrected".
    public var inputIsPCMode: Bool?
    public var pictureMode: String?

    public init(isConnected: Bool, foreground: TVForeground, preferredInput: String, display: DisplayInfo?, inputIsPCMode: Bool? = nil, pictureMode: String? = nil) {
        self.isConnected = isConnected
        self.foreground = foreground
        self.preferredInput = preferredInput
        self.display = display
        self.inputIsPCMode = inputIsPCMode
        self.pictureMode = pictureMode
    }
}

public enum DisplayLockEvaluation: Equatable, Sendable {
    /// The lock does not apply right now, and why.
    case inactive(String)
    case compliant
    case drift([DisplayLockCorrection])
}

/// Pure comparison of a profile against the current state. Every rule has a test.
public enum DisplayLockEvaluator {

    /// The macOS display the profile refers to: the saved one if it is attached, otherwise the
    /// only LG display. Two LG displays without a saved choice is ambiguous and resolves to nil.
    public static func resolveDisplay(profile: DisplayLockProfile, displays: [DisplayInfo]) -> DisplayInfo? {
        if let uuid = profile.displayUUID {
            return displays.first { $0.uuid == uuid }
        }
        let lgDisplays = displays.filter { $0.isLG && !$0.isBuiltIn }
        return lgDisplays.count == 1 ? lgDisplays[0] : nil
    }

    public static func evaluate(profile: DisplayLockProfile, snapshot: DisplayLockSnapshot) -> DisplayLockEvaluation {
        guard profile.isEnabled else { return .inactive("Display Lock is off") }
        guard !profile.isEmpty else { return .inactive("Nothing is locked yet") }
        guard snapshot.isConnected else { return .inactive("Not connected to the TV") }

        let lockedInput = profile.effectiveInputID(preferredInput: snapshot.preferredInput)
        switch snapshot.foreground {
        case .input(let input) where input.rawValue == lockedInput:
            break
        case .input(let input):
            return .inactive("TV is on \(input.displayName)")
        case .app:
            return .inactive("TV is showing an app")
        case .unknown:
            return .inactive("Waiting to learn what the TV is showing")
        }

        var corrections: [DisplayLockCorrection] = []

        if profile.mode != nil || profile.hdrEnabled != nil {
            guard let display = snapshot.display else {
                return .inactive("The TV is not connected to this Mac as a display")
            }
            if let mode = profile.mode, display.currentMode.map({ !$0.matches(mode) }) ?? true {
                corrections.append(.displayMode(mode))
            }
            if let hdrEnabled = profile.hdrEnabled, display.hdrSupported, display.hdrEnabled != hdrEnabled {
                corrections.append(.hdr(hdrEnabled))
            }
        }

        if profile.enforcePCMode, snapshot.inputIsPCMode == false {
            corrections.append(.pcMode)
        }

        if let pictureMode = profile.pictureMode, let current = snapshot.pictureMode, current != pictureMode {
            corrections.append(.pictureMode(pictureMode))
        }

        return corrections.isEmpty ? .compliant : .drift(corrections)
    }
}
