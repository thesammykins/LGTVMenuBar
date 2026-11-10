import Foundation

/// The OLED panel's self-maintenance state, as reported by the TV's panel-care service.
///
/// The TV runs a short pixel refresh on its own after a set number of hours of use, but only
/// while it is switched off. A TV used as a monitor is often never off for long enough, so the
/// refresh falls behind; this is what lets the app notice and make room for it.
public struct PanelCareStatus: Equatable, Sendable {
    /// Total hours the panel has been lit.
    public var panelHours: Int
    /// Panel hours when the last short refresh ran.
    public var shortRefreshLastHours: Int
    /// Hours of use after which a short refresh is due.
    public var shortRefreshIntervalHours: Int
    public var shortRefreshCount: Int
    /// Panel hours when the last long cleaning ran.
    public var longRefreshLastHours: Int
    public var longRefreshIntervalHours: Int
    public var longRefreshCount: Int
    /// The TV's own verdict that a refresh should run at the next opportunity.
    public var isRefreshDue: Bool

    public init(
        panelHours: Int,
        shortRefreshLastHours: Int,
        shortRefreshIntervalHours: Int,
        shortRefreshCount: Int,
        longRefreshLastHours: Int,
        longRefreshIntervalHours: Int,
        longRefreshCount: Int,
        isRefreshDue: Bool
    ) {
        self.panelHours = panelHours
        self.shortRefreshLastHours = shortRefreshLastHours
        self.shortRefreshIntervalHours = shortRefreshIntervalHours
        self.shortRefreshCount = shortRefreshCount
        self.longRefreshLastHours = longRefreshLastHours
        self.longRefreshIntervalHours = longRefreshIntervalHours
        self.longRefreshCount = longRefreshCount
        self.isRefreshDue = isRefreshDue
    }

    public var hoursSinceShortRefresh: Int { max(0, panelHours - shortRefreshLastHours) }
    public var hoursSinceLongRefresh: Int { max(0, panelHours - longRefreshLastHours) }

    /// Hours past the point where the short refresh should have run.
    public var shortRefreshOverdueHours: Int { max(0, hoursSinceShortRefresh - shortRefreshIntervalHours) }

    public var isLongRefreshDue: Bool {
        longRefreshIntervalHours > 0 && hoursSinceLongRefresh >= longRefreshIntervalHours
    }

    /// Shell command that prints the three panel-care replies as `key=json` lines.
    static let queryCommand = [
        #"echo "utt=$(luna-send -n 1 luna://com.webos.service.oledepl/getOledPanelUTT '{}' 2>/dev/null)""#,
        #"echo "info=$(luna-send -n 1 luna://com.webos.service.oledepl/getPixelRefresherInfoList '{}' 2>/dev/null)""#,
        #"echo "cond=$(luna-send -n 1 luna://com.webos.service.oledepl/isPixelRefresherCondition '{}' 2>/dev/null)""#
    ].joined(separator: "; ")

    /// Parses the output of `queryCommand`. Returns nil unless all three replies are present,
    /// so a TV without the service (an LCD, or different firmware) reads as "not available".
    static func parse(_ output: String) -> PanelCareStatus? {
        var replies: [String: [String: Any]] = [:]
        for line in output.split(whereSeparator: \.isNewline) {
            guard let separator = line.firstIndex(of: "=") else { continue }
            let value = String(line[line.index(after: separator)...])
            if let data = value.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               json["returnValue"] as? Bool == true {
                replies[String(line[..<separator])] = json
            }
        }

        guard let panelHours = replies["utt"]?["oledPanelUTT"] as? Int,
              let info = replies["info"],
              let isDue = replies["cond"]?["isCondition"] as? Bool else {
            return nil
        }

        return PanelCareStatus(
            panelHours: panelHours,
            shortRefreshLastHours: info["offrsLastTime"] as? Int ?? panelHours,
            shortRefreshIntervalHours: info["offrsInterval"] as? Int ?? 0,
            shortRefreshCount: info["offrsCount"] as? Int ?? 0,
            longRefreshLastHours: info["jbLastTime"] as? Int ?? panelHours,
            longRefreshIntervalHours: info["jbInterval"] as? Int ?? 0,
            longRefreshCount: info["jbCount"] as? Int ?? 0,
            isRefreshDue: isDue
        )
    }
}
