import SwiftUI

/// The wording of the Panel Care readout, kept apart from the view so it can be tested.
struct PanelCarePresentation: Equatable {
    let lastRefresh: String
    let useSinceLastRefresh: String?
    let nextRefresh: String
    let tvSchedule: String?

    init(status: PanelCareStatus, history: PanelCareHistory?, now: Date = Date()) {
        let hoursSince = history?.hoursOfUseSinceLastRefresh(status)

        if let refresh = history?.lastRefresh, hoursSince != nil {
            let formatter = RelativeDateTimeFormatter()
            formatter.dateTimeStyle = .named
            lastRefresh = formatter.localizedString(for: refresh.observedAt, relativeTo: now)
        } else {
            lastRefresh = "Not seen by this app yet"
        }
        useSinceLastRefresh = hoursSince.map(Self.hours)

        if status.isRefreshDue {
            nextRefresh = "Due now"
        } else if let hoursSince, let interval = status.refreshIntervalHours {
            let remaining = interval - hoursSince
            // The TV's own flag is the authority; the estimate only says how far off it is.
            nextRefresh = remaining > 0 ? "After about \(Self.hours(remaining)) more of use" : "Soon"
        } else {
            nextRefresh = "Not due yet"
        }

        tvSchedule = status.refreshIntervalHours.map { "After every \(Self.hours($0)) of use, once the TV is off" }
    }

    static func hours(_ count: Int) -> String {
        count == 1 ? "1 hour" : "\(count.formatted()) hours"
    }
}

/// The OLED panel's pixel refresh: when it last ran, when the next is due, and making room for it.
struct PanelCareSettingsPane: View {
    let controller: TVController

    var body: some View {
        Form {
            if let status = controller.panelCare {
                statusSection(status)
                timingSection(status)
                detailSection(status)
            } else {
                Section("Pixel Refresh") {
                    unavailableNotice
                }
            }
        }
        .formStyle(.grouped)
        .task {
            await controller.refreshPanelCare()
        }
    }

    @ViewBuilder
    private var unavailableNotice: some View {
        if controller.rootAccess.isUsable {
            InlineNotice(kind: .info, text: controller.connectionState.isConnected ? "This TV does not report panel-care information." : "Connect to the TV to see its panel-care state.")
        } else {
            InlineNotice(kind: .info, text: "Panel care needs root access to the TV, set up in the Advanced pane. Without it the app cannot tell when a pixel refresh is due.")
        }
    }

    private func statusSection(_ status: PanelCareStatus) -> some View {
        let presentation = PanelCarePresentation(status: status, history: controller.panelCareHistory)
        return Section {
            LabeledContent("Last refresh", value: presentation.lastRefresh)
            if let use = presentation.useSinceLastRefresh {
                LabeledContent("Use since then", value: use)
            }
            LabeledContent("Next refresh", value: presentation.nextRefresh)
            if let schedule = presentation.tvSchedule {
                LabeledContent("TV's schedule", value: schedule)
            }

            if controller.pixelRefreshStartedAt != nil {
                InlineNotice(kind: .info, text: "The TV is off for a pixel refresh.")
            }
        } header: {
            Text("Pixel Refresh")
        } footer: {
            SectionFooter("The TV decides when a refresh is due and runs it by itself, but only while it is switched off. The schedule above is the TV's own. The app times the last refresh from when it first sees the TV's count go up.")
        }
    }

    private func timingSection(_ status: PanelCareStatus) -> some View {
        let isEnabled = controller.configuration?.refreshPixelsDuringDowntime == true
        let limitsToHours = controller.configuration?.panelCareSchedule.limitsToHours == true
        return Section {
            Toggle("Switch the TV off for a due refresh", isOn: controller.configurationBinding(\.refreshPixelsDuringDowntime, default: false))

            Picker("When", selection: controller.configurationBinding(\.panelCareSchedule.limitsToHours, default: false)) {
                Text("Whenever the Mac is locked or asleep").tag(false)
                Text("Only during set hours").tag(true)
            }
            .disabled(!isEnabled)

            if limitsToHours {
                DatePicker("From", selection: timeBinding(\.panelCareSchedule.startMinute, default: 60), displayedComponents: .hourAndMinute)
                    .disabled(!isEnabled)
                DatePicker("Until", selection: timeBinding(\.panelCareSchedule.endMinute, default: 360), displayedComponents: .hourAndMinute)
                    .disabled(!isEnabled)
            }

            if status.isRefreshDue, controller.pixelRefreshStartedAt == nil {
                InlineNotice(kind: .info, text: dueNotice(isEnabled: isEnabled, limitsToHours: limitsToHours))
            }
        } header: {
            Text("Making Room for It")
        } footer: {
            SectionFooter("A TV used as a monitor is rarely off for long enough to refresh. With this on, when a refresh is due the TV is switched off a minute after the Mac is locked, or when the Mac sleeps, and is left alone for up to ten minutes. Set hours narrow that to part of the day, such as overnight. It never happens while the Mac is in use, and unlocking brings the TV straight back.")
        }
    }

    private func detailSection(_ status: PanelCareStatus) -> some View {
        Section("Panel") {
            LabeledContent("Panel use", value: PanelCarePresentation.hours(status.panelHours))
            LabeledContent("Refreshes run", value: status.refreshCount.formatted())
            LabeledContent("Long cleanings run", value: longCleaningText(status))
        }
    }

    private func longCleaningText(_ status: PanelCareStatus) -> String {
        guard let interval = status.longRefreshIntervalHours else { return status.longRefreshCount.formatted() }
        return "\(status.longRefreshCount.formatted()), one every \(PanelCarePresentation.hours(interval)) of use"
    }

    private func dueNotice(isEnabled: Bool, limitsToHours: Bool) -> String {
        guard isEnabled else {
            return "A refresh is due. Turn this on, or switch the TV off for ten minutes when you are finished with it."
        }
        return limitsToHours
            ? "A refresh is due. It will run the next time the Mac is locked or asleep during the set hours."
            : "A refresh is due. It will run the next time the Mac is locked or asleep."
    }

    /// Bridges a minutes-after-midnight setting to the time-of-day picker.
    private func timeBinding(_ keyPath: WritableKeyPath<TVConfiguration, Int>, default defaultValue: Int) -> Binding<Date> {
        let minutes = controller.configurationBinding(keyPath, default: defaultValue)
        let calendar = Calendar.current
        return Binding(
            get: {
                calendar.date(bySettingHour: minutes.wrappedValue / 60, minute: minutes.wrappedValue % 60, second: 0, of: Date()) ?? Date()
            },
            set: { newValue in
                let parts = calendar.dateComponents([.hour, .minute], from: newValue)
                minutes.wrappedValue = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
        )
    }
}
