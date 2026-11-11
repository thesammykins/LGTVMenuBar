import Foundation

/// What the app has seen of the TV's pixel refreshes, kept between launches.
///
/// The TV reports a count of refreshes and a "last refresh" figure on a clock of its own that
/// does not line up with its panel hours. So the app notes the panel hours and the time when it
/// first sees the count go up, and measures use since the last refresh from that.
public struct PanelCareHistory: Codable, Equatable, Sendable {
    public struct Refresh: Codable, Equatable, Sendable {
        /// Panel hours when the app first saw this refresh.
        public var panelHours: Int
        public var observedAt: Date

        public init(panelHours: Int, observedAt: Date) {
            self.panelHours = panelHours
            self.observedAt = observedAt
        }
    }

    public var refreshCount: Int
    /// Nil until the app has seen the count go up at least once.
    public var lastRefresh: Refresh?

    public init(refreshCount: Int, lastRefresh: Refresh? = nil) {
        self.refreshCount = refreshCount
        self.lastRefresh = lastRefresh
    }

    /// The history after reading `status` at `date`.
    public static func updated(_ history: PanelCareHistory?, with status: PanelCareStatus, at date: Date) -> PanelCareHistory {
        guard let history, status.refreshCount >= history.refreshCount else {
            // First reading, or a count that went down: a different or reset TV. Start again.
            return PanelCareHistory(refreshCount: status.refreshCount)
        }
        guard status.refreshCount > history.refreshCount else { return history }
        return PanelCareHistory(
            refreshCount: status.refreshCount,
            lastRefresh: Refresh(panelHours: status.panelHours, observedAt: date)
        )
    }

    /// Hours the panel has been lit since the last refresh the app saw.
    public func hoursOfUseSinceLastRefresh(_ status: PanelCareStatus) -> Int? {
        guard let lastRefresh, status.refreshCount == refreshCount else { return nil }
        return max(0, status.panelHours - lastRefresh.panelHours)
    }
}

/// Where the history is kept. The app uses UserDefaults; tests keep it in memory.
@MainActor
public protocol PanelCareHistoryStoring: AnyObject {
    func load() -> PanelCareHistory?
    /// Nil forgets the record.
    func save(_ history: PanelCareHistory?)
}

@MainActor
public final class UserDefaultsPanelCareHistoryStore: PanelCareHistoryStoring {
    private let defaults: UserDefaults
    private let key = "panelCareHistory"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> PanelCareHistory? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(PanelCareHistory.self, from: data)
    }

    public func save(_ history: PanelCareHistory?) {
        guard let history, let data = try? JSONEncoder().encode(history) else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(data, forKey: key)
    }
}
