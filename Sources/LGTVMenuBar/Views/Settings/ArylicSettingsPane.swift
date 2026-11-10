#if LOCAL_ARYLIC_BUILD
import SwiftUI

/// Arylic amplifier used for volume instead of the TV (local builds only).
struct ArylicSettingsPane: View {
    @Bindable var controller: TVController

    @State private var host = ""
    @State private var port = "8899"
    @State private var timeout = "5"
    @State private var message: (kind: InlineNotice.Kind, text: String)?
    @State private var isTesting = false

    private var parsedSettings: ArylicSettings? {
        guard InputValidation.host(host) == nil,
              let portNumber = Int(port), (1...65_535).contains(portNumber),
              let timeoutSeconds = Double(timeout), timeoutSeconds > 0 else { return nil }
        return ArylicSettings(host: host.trimmingCharacters(in: .whitespaces), port: portNumber, timeout: timeoutSeconds)
    }

    var body: some View {
        Form {
            Section("Device") {
                TextField("Address", text: $host, prompt: Text("192.168.1.50 or arylic.local"))
                TextField("Port", text: $port, prompt: Text("8899"))
                TextField("Timeout (seconds)", text: $timeout, prompt: Text("5"))
            }

            Section("Status") {
                LabeledContent("Volume goes to", value: controller.volumeControlTarget == .arylic ? "Arylic" : "TV")
                LabeledContent("Saved device", value: controller.arylicSettings.map { "\($0.host):\($0.port)" } ?? "None")
                if let message {
                    InlineNotice(kind: message.kind, text: message.text)
                }
                HStack {
                    Button("Test Connection", action: testConnection)
                        .disabled(parsedSettings == nil || isTesting)
                    if isTesting {
                        ProgressView().controlSize(.small)
                    }
                    Button("Save", action: save)
                        .buttonStyle(.borderedProminent)
                        .disabled(parsedSettings == nil)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            if let settings = controller.arylicSettings {
                host = settings.host
                port = String(settings.port)
                timeout = String(format: "%g", settings.timeout)
            }
        }
    }

    private func save() {
        guard let settings = parsedSettings else { return }
        controller.arylicSettings = settings
        message = (.success, "Saved.")
    }

    private func testConnection() {
        guard let settings = parsedSettings else { return }
        isTesting = true
        message = nil
        Task {
            defer { isTesting = false }
            do {
                let status = try await ArylicVolumeClient(settings: settings).getPlayerStatus()
                message = (.success, "Connected. Volume \(status.volume)\(status.isMuted ? ", muted" : "").")
            } catch {
                message = (.failure, error.localizedDescription)
            }
        }
    }
}
#endif
