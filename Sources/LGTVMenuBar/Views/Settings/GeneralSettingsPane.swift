import SwiftUI
import AppKit

/// App-level behaviour: login item, keyboard volume keys, updates.
struct GeneralSettingsPane: View {
    @Bindable var controller: TVController
    let softwareUpdates: SoftwareUpdateController?

    @State private var launchAtLogin = false
    @State private var launchAtLoginProblem: String?
    @State private var hasAccessibilityPermission = true

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "–"
        return "\(version) (\(build))"
    }

    var body: some View {
        Form {
            Section {
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        setLaunchAtLogin(newValue)
                    }
                if let launchAtLoginProblem {
                    InlineNotice(kind: .failure, text: launchAtLoginProblem)
                }
            }

            Section {
                Toggle("Use the keyboard volume keys for the TV", isOn: $controller.isMediaKeyControlEnabled)

                if !hasAccessibilityPermission {
                    InlineNotice(kind: .warning, text: "macOS needs your permission before the app can see the volume keys.")
                    Button("Open Accessibility Settings…", action: requestAccessibilityPermission)
                } else if controller.isMediaKeyControlEnabled {
                    InlineNotice(
                        kind: controller.connectionState.isConnected ? .success : .info,
                        text: controller.connectionState.isConnected ? "The volume keys control the TV." : "The volume keys will control the TV once it is connected."
                    )
                }

                #if LOCAL_ARYLIC_BUILD
                Toggle("Send volume to the Arylic device", isOn: $controller.isArylicVolumeControlEnabled)
                #endif
            } header: {
                Text("Volume Keys")
            } footer: {
                if !hasAccessibilityPermission {
                    SectionFooter("Turn on LGTV Menu Bar under Privacy & Security › Accessibility. If it is already on, remove it from the list and add it again; macOS forgets the permission when the app is rebuilt.")
                }
            }

            Section("Updates") {
                if let softwareUpdates, softwareUpdates.isEnabled {
                    Toggle("Check for updates automatically", isOn: Binding(
                        get: { softwareUpdates.automaticallyChecksForUpdates },
                        set: { softwareUpdates.automaticallyChecksForUpdates = $0 }
                    ))
                    Button("Check for Updates…") {
                        softwareUpdates.checkForUpdates()
                    }
                    .disabled(!softwareUpdates.canCheckForUpdates)
                    if let lastChecked = softwareUpdates.lastUpdateCheckDate {
                        LabeledContent("Last checked", value: lastChecked.formatted(date: .abbreviated, time: .shortened))
                    }
                } else {
                    InlineNotice(kind: .info, text: "This build does not update itself.")
                }
            }

            Section("About") {
                LabeledContent("LGTV Menu Bar", value: appVersion)
            }
        }
        .formStyle(.grouped)
        .task {
            launchAtLogin = (try? await controller.isLaunchAtLoginEnabled()) ?? false
            await watchAccessibilityPermission()
        }
    }

    /// Polls while the pane is visible and permission is missing; the task ends with the view.
    private func watchAccessibilityPermission() async {
        while !Task.isCancelled {
            let granted = controller.hasAccessibilityPermission()
            if granted != hasAccessibilityPermission {
                hasAccessibilityPermission = granted
                if granted {
                    controller.refreshMediaKeyCapture()
                }
            }
            try? await Task.sleep(for: .seconds(granted ? 10 : 1.5))
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLoginProblem = nil
        Task {
            do {
                guard (try? await controller.isLaunchAtLoginEnabled()) != enabled else { return }
                try await controller.setLaunchAtLogin(enabled)
            } catch {
                launchAtLoginProblem = error.localizedDescription
                launchAtLogin = (try? await controller.isLaunchAtLoginEnabled()) ?? false
            }
        }
    }

    private func requestAccessibilityPermission() {
        if !controller.requestAccessibilityPermission(),
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
