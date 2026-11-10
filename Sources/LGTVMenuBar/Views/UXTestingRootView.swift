import SwiftUI

#if UX_TESTING_APP
/// Regular-window harness for accessibility, screenshot, and layout validation.
struct UXTestingRootView: View {
    let controller: TVController
    let displayLock: DisplayLockController

    @State private var pane: SettingsWindowController.Pane = .tv

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("LGTV Menu Bar UX Validation")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Fixture state is a connected LG C2. Nothing here talks to a real TV.")
                        .foregroundStyle(.secondary)
                }

                HStack(alignment: .top, spacing: 20) {
                    panel("Menu Bar Popover") {
                        MenuBarView(controller: controller, displayLock: displayLock)
                            .background(.background, in: RoundedRectangle(cornerRadius: 10))
                    }

                    panel("Settings") {
                        Picker("Pane", selection: $pane) {
                            ForEach([SettingsWindowController.Pane.tv, .automation, .display, .panelCare, .general, .advanced], id: \.self) { pane in
                                Text(pane.title).tag(pane)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()

                        Group {
                            switch pane {
                            case .tv: TVSettingsPane(controller: controller)
                            case .automation: AutomationSettingsPane(controller: controller)
                            case .display: DisplaySettingsPane(controller: controller, displayLock: displayLock)
                            case .panelCare: PanelCareSettingsPane(controller: controller)
                            case .general: GeneralSettingsPane(controller: controller, softwareUpdates: nil)
                            case .advanced, .arylic: AdvancedSettingsPane(controller: controller)
                            }
                        }
                        .frame(width: SettingsWindowController.paneWidth, height: pane.height)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.regularMaterial)
    }

    private func panel<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content()
        }
    }
}
#endif
