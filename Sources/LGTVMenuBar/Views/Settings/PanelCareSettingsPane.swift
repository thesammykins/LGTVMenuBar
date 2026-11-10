import SwiftUI

/// The OLED panel's pixel refresh: how far behind it is, and making room for it.
struct PanelCareSettingsPane: View {
    let controller: TVController

    var body: some View {
        Form {
            panelCareSection
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var panelCareSection: some View {
        Section {
            if let status = controller.panelCare {
                LabeledContent("Panel use", value: "\(status.panelHours.formatted()) hours")
                LabeledContent("Since the last pixel refresh") {
                    Text(refreshSummary(status))
                        .foregroundStyle(status.isRefreshDue ? .primary : .secondary)
                }
                if status.isLongRefreshDue {
                    InlineNotice(kind: .info, text: "The long pixel cleaning is also due (\(status.hoursSinceLongRefresh) of \(status.longRefreshIntervalHours) hours). The TV runs it by itself during a longer spell switched off, and it takes about an hour.")
                }

                Toggle("Run a due pixel refresh while the Mac is locked or asleep", isOn: controller.configurationBinding(\.refreshPixelsDuringDowntime, default: false))

                if controller.pixelRefreshStartedAt != nil {
                    InlineNotice(kind: .info, text: "The TV is off for a pixel refresh.")
                } else if status.isRefreshDue {
                    InlineNotice(kind: .info, text: controller.configuration?.refreshPixelsDuringDowntime == true
                        ? "A refresh is due. It will run the next time the Mac is locked or asleep."
                        : "A refresh is due. Turn this on, or switch the TV off for ten minutes when you are finished with it.")
                }
            } else if controller.rootAccess.isUsable {
                InlineNotice(kind: .info, text: controller.connectionState.isConnected ? "This TV does not report panel-care information." : "Connect to the TV to see its panel-care state.")
            } else {
                InlineNotice(kind: .info, text: "Panel care needs root access to the TV, set up in the Advanced pane. Without it the app cannot tell when a pixel refresh is due.")
            }
        } header: {
            Text("Panel Care")
        } footer: {
            SectionFooter("An OLED TV refreshes its pixels by itself after every few hours of use, but only while it is switched off, which a TV used as a monitor rarely is for long. With this on, when a refresh is due the TV is switched off a minute after the Mac is locked, or when the Mac sleeps, and is left alone for up to ten minutes. It never happens while the Mac is in use, and unlocking brings the TV straight back.")
        }
        .task {
            await controller.refreshPanelCare()
        }
    }

    private func refreshSummary(_ status: PanelCareStatus) -> String {
        let since = "\(status.hoursSinceShortRefresh) hours"
        guard status.shortRefreshIntervalHours > 0 else { return since }
        return status.isRefreshDue
            ? "\(since) (due every \(status.shortRefreshIntervalHours))"
            : "\(since) of \(status.shortRefreshIntervalHours)"
    }
}
