import SwiftUI

#if UX_TESTING_APP
/// Regular-window harness for accessibility, screenshot, and layout validation.
struct UXTestingRootView: View {
    @Bindable var controller: TVController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                HStack(alignment: .top, spacing: 20) {
                    validationPanel("Menu Bar Popover") {
                        MenuBarView(controller: controller)
                            .frame(width: 420)
                    }

                    validationPanel("Settings Surface") {
                        SettingsView(controller: controller)
                            .frame(width: 460, height: 420)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.regularMaterial)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("LGTV Menu Bar UX Validation")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Fixture state uses a connected LG C2 over secure WebSocket and does not auto-connect to a real TV.")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func validationPanel<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
#endif
