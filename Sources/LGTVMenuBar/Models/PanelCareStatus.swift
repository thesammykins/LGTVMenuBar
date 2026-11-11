import Foundation

/// The OLED panel's self-maintenance state, as reported by the TV's panel-care service.
///
/// The TV runs a short pixel refresh on its own after a set number of hours of use, but only
/// while it is switched off. A TV used as a monitor is often never off for long enough, so the
/// refresh falls behind; this is what lets the app notice and make room for it.
public struct PanelCareStatus: Equatable, Sendable {
    /// Total hours the panel has been lit.
    public var panelHours: Int
    /// How many short pixel refreshes the TV has run. Going up is the evidence that one ran.
    public var refreshCount: Int
    /// How many long pixel cleanings the TV has run.
    public var longRefreshCount: Int
    /// The TV's own verdict that a refresh should run at the next opportunity.
    public var isRefreshDue: Bool
    /// Hours of use after which the TV asks for a short refresh, as the TV reports it.
    public var refreshIntervalHours: Int?
    /// Hours of use between long cleanings, as the TV reports it.
    public var longRefreshIntervalHours: Int?

    public init(
        panelHours: Int,
        refreshCount: Int,
        longRefreshCount: Int,
        isRefreshDue: Bool,
        refreshIntervalHours: Int? = nil,
        longRefreshIntervalHours: Int? = nil
    ) {
        self.panelHours = panelHours
        self.refreshCount = refreshCount
        self.longRefreshCount = longRefreshCount
        self.isRefreshDue = isRefreshDue
        self.refreshIntervalHours = refreshIntervalHours
        self.longRefreshIntervalHours = longRefreshIntervalHours
    }

    // The TV also reports `offrsLastTime` and `jbLastTime`. They are not on the same clock as the
    // panel hours (two refreshes 10 panel hours apart were reported 8 apart, about 100 behind),
    // so nothing is derived from them. Use since the last refresh comes from `PanelCareHistory`,
    // and whether a refresh is due comes only from the TV's own flag.

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
            refreshCount: info["offrsCount"] as? Int ?? 0,
            longRefreshCount: info["jbCount"] as? Int ?? 0,
            isRefreshDue: isDue,
            refreshIntervalHours: (info["offrsInterval"] as? Int).flatMap { $0 > 0 ? $0 : nil },
            longRefreshIntervalHours: (info["jbInterval"] as? Int).flatMap { $0 > 0 ? $0 : nil }
        )
    }
}
