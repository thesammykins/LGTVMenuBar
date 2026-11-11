import Foundation

/// Current WebOS TV power and screen state.
public struct TVPowerStatus: Equatable, Sendable {
    public enum NormalizedState: String, Sendable {
        case active
        case screenOff
        case screenOnInProgress
        case off
        case turningOff
        /// Off to the viewer but still answering. Reported both while the pixel refresher runs
        /// and as the ordinary standby of a TV that keeps its network up; the two look the same.
        case activeStandby
        case screenSaver
        case unknown
    }

    public let state: String?
    public let processing: String?
    public let powerOnReason: String?

    public init(state: String? = nil, processing: String? = nil, powerOnReason: String? = nil) {
        self.state = state
        self.processing = processing
        self.powerOnReason = powerOnReason
    }

    public init(payload: [String: Any]) {
        self.init(
            state: payload["state"] as? String,
            processing: payload["processing"] as? String,
            powerOnReason: payload["powerOnReason"] as? String
        )
    }

    public var normalizedState: NormalizedState {
        let normalizedState = state?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedProcessing = processing?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if normalizedProcessing == "request suspend" {
            return .turningOff
        }

        if normalizedState == "active standby" {
            return .activeStandby
        }

        if normalizedState == "screen saver" {
            return .screenSaver
        }

        if normalizedState == "screen off" {
            if normalizedProcessing == "screen on" {
                return .screenOnInProgress
            }
            return .screenOff
        }

        if normalizedState == "active" {
            return .active
        }

        if normalizedState == "suspend" {
            return .off
        }

        return .unknown
    }

    public var diagnosticMetadata: [String: String] {
        [
            "powerState": state ?? "unknown",
            "powerProcessing": processing ?? "none",
            "powerOnReason": powerOnReason ?? "none",
            "normalizedPowerState": normalizedState.rawValue
        ]
    }
}
