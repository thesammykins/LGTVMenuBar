import Foundation

/// Delay before each automatic reconnect check after the connection is lost.
///
/// Checks start quickly, back off to once a minute and then stay there. A check is a single TCP
/// probe, and a full connect only follows when the TV answers, so the steady state costs one
/// packet a minute and never wakes or prompts the TV.
public enum ReconnectSchedule {
    public static let initialDelay: TimeInterval = 2
    public static let maximumDelay: TimeInterval = 60

    public static func delay(forAttempt attempt: Int) -> Duration {
        let clamped = max(0, min(attempt, 10))
        let seconds = min(initialDelay * pow(2, Double(clamped)), maximumDelay)
        return .seconds(seconds)
    }

    /// Log the first few checks and then only powers of two, so a TV left off overnight does not
    /// fill the diagnostic log.
    public static func shouldLog(attempt: Int) -> Bool {
        attempt < 4 || (attempt & (attempt - 1)) == 0
    }
}
