import Foundation

/// When the app may switch the TV off for a due pixel refresh.
///
/// This only ever narrows the rule that the Mac must be locked or asleep. It cannot make a
/// refresh happen while the Mac is in use.
public struct PanelCareSchedule: Codable, Equatable, Sendable {
    /// Off: any time the Mac is locked. On: only between `startMinute` and `endMinute`.
    public var limitsToHours: Bool
    /// Minutes after midnight, local time.
    public var startMinute: Int
    public var endMinute: Int

    public init(limitsToHours: Bool = false, startMinute: Int = 60, endMinute: Int = 360) {
        self.limitsToHours = limitsToHours
        self.startMinute = startMinute
        self.endMinute = endMinute
    }

    /// The start is included and the end is not. A range that ends before it starts runs past
    /// midnight; equal ends mean the whole day.
    public func allows(minuteOfDay minute: Int) -> Bool {
        guard limitsToHours, startMinute != endMinute else { return true }
        if startMinute < endMinute {
            return (startMinute..<endMinute).contains(minute)
        }
        return minute >= startMinute || minute < endMinute
    }

    public func allows(_ date: Date, calendar: Calendar = .current) -> Bool {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return allows(minuteOfDay: (parts.hour ?? 0) * 60 + (parts.minute ?? 0))
    }

    /// The next time the allowed hours begin, or nil when there is nothing to wait for.
    public func nextStart(after date: Date, calendar: Calendar = .current) -> Date? {
        guard limitsToHours, startMinute != endMinute else { return nil }
        let start = DateComponents(hour: startMinute / 60, minute: startMinute % 60, second: 0)
        return calendar.nextDate(after: date, matching: start, matchingPolicy: .nextTime)
    }
}
