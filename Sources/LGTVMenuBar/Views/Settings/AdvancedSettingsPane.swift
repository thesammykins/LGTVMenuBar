import SwiftUI
import AppKit

/// Optional root shell access, and diagnostics.
struct AdvancedSettingsPane: View {
    let controller: TVController

    @State private var password = ""
    @State private var isWorking = false
    @State private var rootMessage: (kind: InlineNotice.Kind, text: String)?
    @State private var hasAppKey = false
    @State private var hasPassword = false
    @State private var showingForgetConfirmation = false

    @State private var isLoggingEnabled = false
    @State private var isDebugMode = false
    @State private var entryCount = 0
    @State private var recentEntryCount = 0
    @State private var diagnosticsMessage: (kind: InlineNotice.Kind, text: String)?
    @State private var isCapturingDeviceDetails = false
    @State private var showingClearLogsConfirmation = false

    var body: some View {
        Form {
            if let config = controller.configuration {
                rootSection(config)
                if config.rootAccess.isEnabled {
                    shellStatusSection(config)
                }
            }
            diagnosticsSection
        }
        .formStyle(.grouped)
        .task {
            refreshSecretState()
            loadDiagnosticState()
            while !Task.isCancelled {
                updateCounts()
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .confirmationDialog("Remove saved shell credentials?", isPresented: $showingForgetConfirmation) {
            Button("Remove Credentials", role: .destructive, action: forgetCredentials)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The app's SSH key, any saved password and the remembered host key are deleted from this Mac. The key stays in the TV's authorized_keys file until you remove it there.")
        }
        .confirmationDialog("Clear the diagnostic log?", isPresented: $showingClearLogsConfirmation) {
            Button("Clear Log", role: .destructive) {
                controller.diagnosticLogger.clear()
                updateCounts()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Root Access

    private var root: RootAccessService { controller.rootAccess }

    @ViewBuilder
    private func rootSection(_ config: TVConfiguration) -> some View {
        let settings = config.rootAccess

        Section {
            Toggle("My TV is rooted", isOn: controller.configurationBinding(\.rootAccess.isEnabled, default: false))

            if settings.isEnabled {
                Picker("Connect with", selection: transportBinding) {
                    ForEach(RootAccessSettings.Transport.allCases) { transport in
                        Text(transport.displayName).tag(transport)
                    }
                }
                .pickerStyle(.segmented)

                CommittedTextField(
                    title: "Address",
                    prompt: "Same as the TV (\(config.ipAddress))",
                    value: settings.hostOverride,
                    validate: InputValidation.optionalHost
                ) { value in
                    // A different host has a different host key.
                    update { $0.rootAccess.hostOverride = value; $0.rootAccess.trustedHostKeyFingerprint = nil }
                }
                if settings.usesDifferentHost(than: config.ipAddress) {
                    InlineNotice(kind: .warning, text: "Shell commands will go to \(settings.effectiveHost(tvAddress: config.ipAddress)), not to the TV at \(config.ipAddress). Leave the address empty unless the TV really has two addresses.")
                }

                CommittedTextField(
                    title: "Port",
                    prompt: String(settings.transport.defaultPort),
                    value: settings.port.map(String.init) ?? "",
                    validate: InputValidation.optionalPort
                ) { value in
                    update { $0.rootAccess.port = Int(value) }
                }

                CommittedTextField(title: "User name", prompt: "root", value: settings.username) { value in
                    update { $0.rootAccess.username = value.isEmpty ? "root" : value }
                }

                switch settings.transport {
                case .ssh:
                    sshCredentialRows(settings)
                case .telnet:
                    InlineNotice(kind: .warning, text: "Telnet is not encrypted, and Homebrew Channel's Telnet has no password: anyone on your network can use it. Use SSH if the TV offers it.")
                }
            }
        } header: {
            Text("Rooted TV")
        } footer: {
            SectionFooter("Optional, for TVs rooted with Homebrew Channel. A root shell lets the app change settings the normal connection cannot, such as the picture mode, without the on-screen workaround. Everything else in the app works without it.")
        }
    }

    @ViewBuilder
    private func sshCredentialRows(_ settings: RootAccessSettings) -> some View {
        Picker("Sign in with", selection: controller.configurationBinding(\.rootAccess.authentication, default: .appKey)) {
            ForEach(RootAccessSettings.Authentication.allCases) { method in
                Text(method.displayName).tag(method)
            }
        }

        switch settings.authentication {
        case .appKey:
            LabeledContent("Key", value: hasAppKey ? "Stored in the Keychain" : "Not created yet")
            SecureField("TV password", text: $password, prompt: Text("Used once to install the key"))
            Button(hasAppKey ? "Install Key on TV Again" : "Create Key and Install on TV", action: installKey)
                .disabled(isWorking)
            Text("The app creates its own key, keeps the private half in the Keychain and adds the public half to the TV. Homebrew Channel's default password is “alpine”. Once a key is installed, the TV stops accepting the password after its next restart.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        case .password:
            SecureField("Password", text: $password, prompt: Text(hasPassword ? "Saved in the Keychain" : "Required"))
            Button("Save Password", action: savePassword)
                .disabled(password.isEmpty)
        }
    }

    @ViewBuilder
    private func shellStatusSection(_ config: TVConfiguration) -> some View {
        Section("Shell Status") {
            switch root.status {
            case .disabled, .notChecked:
                InlineNotice(kind: .info, text: "Not tested yet.")
            case .checking:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Connecting…")
                }
            case .available(let capabilities):
                InlineNotice(kind: .success, text: "Root shell is working.")
                LabeledContent("Kernel", value: capabilities.kernel.isEmpty ? "–" : capabilities.kernel)
                LabeledContent("Settings service", value: capabilities.hasLunaSend ? "Available" : "luna-send not found")
                if let pictureMode = capabilities.pictureMode {
                    LabeledContent("Picture mode", value: pictureMode)
                }
                if let powerState = capabilities.powerState {
                    LabeledContent("Power state", value: powerState)
                }
            case .failed(let message):
                InlineNotice(kind: .failure, text: message)
            }

            if let rootMessage {
                InlineNotice(kind: rootMessage.kind, text: rootMessage.text)
            }

            Button("Test Connection", action: testConnection)
                .disabled(isWorking || root.status == .checking)

            if let fingerprint = config.rootAccess.trustedHostKeyFingerprint {
                LabeledContent("Host key") {
                    Text(fingerprint)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Button("Forget Host Key") {
                    update { $0.rootAccess.trustedHostKeyFingerprint = nil }
                    rootMessage = (.info, "The next connection will trust whichever key the TV presents.")
                }
            }

            Button("Remove Saved Credentials…", role: .destructive) {
                showingForgetConfirmation = true
            }
            .disabled(!hasAppKey && !hasPassword && config.rootAccess.trustedHostKeyFingerprint == nil)
        }
    }

    private var transportBinding: Binding<RootAccessSettings.Transport> {
        Binding(
            get: { controller.configuration?.rootAccess.transport ?? .ssh },
            set: { transport in
                // The port and host key belong to the other service.
                update {
                    $0.rootAccess.transport = transport
                    $0.rootAccess.port = nil
                    $0.rootAccess.trustedHostKeyFingerprint = nil
                }
            }
        )
    }

    private func update(_ mutate: (inout TVConfiguration) -> Void) {
        do {
            try controller.updateConfiguration(mutate)
        } catch {
            rootMessage = (.failure, error.localizedDescription)
        }
    }

    private func refreshSecretState() {
        guard let config = controller.configuration else { return }
        hasAppKey = root.hasAppKey(for: config)
        hasPassword = root.hasPassword(for: config)
    }

    private func testConnection() {
        rootMessage = nil
        isWorking = true
        Task {
            defer { isWorking = false }
            await root.refresh()
        }
    }

    private func installKey() {
        rootMessage = nil
        isWorking = true
        let oneTimePassword = password
        Task {
            defer {
                isWorking = false
                refreshSecretState()
            }
            do {
                try await root.installAppKey(usingPassword: oneTimePassword)
                password = ""
                rootMessage = (.success, "The key is installed. Testing it now…")
                if case .available = await root.refresh() {
                    rootMessage = (.success, "The key is installed and working.")
                } else {
                    rootMessage = nil
                }
            } catch {
                rootMessage = (.failure, error.localizedDescription)
            }
        }
    }

    private func savePassword() {
        guard let config = controller.configuration else { return }
        do {
            try root.setPassword(password, for: config)
            password = ""
            refreshSecretState()
            rootMessage = (.success, "Password saved in the Keychain.")
        } catch {
            rootMessage = (.failure, error.localizedDescription)
        }
    }

    private func forgetCredentials() {
        guard let config = controller.configuration else { return }
        root.forgetSecrets(for: config)
        update { $0.rootAccess.trustedHostKeyFingerprint = nil }
        refreshSecretState()
        rootMessage = (.info, "Saved credentials removed.")
    }

    // MARK: - Diagnostics

    private var diagnosticsSection: some View {
        Section {
            Toggle("Record a diagnostic log", isOn: $isLoggingEnabled)
                .onChange(of: isLoggingEnabled) { _, newValue in
                    guard newValue != controller.diagnosticLogger.isEnabled else { return }
                    controller.setDiagnosticLoggingEnabled(newValue)
                    updateCounts()
                }
            Toggle("Include routine events", isOn: $isDebugMode)
                .disabled(!isLoggingEnabled)
                .onChange(of: isDebugMode) { _, newValue in
                    guard newValue != controller.diagnosticLogger.isDebugMode else { return }
                    controller.setDiagnosticDebugMode(newValue)
                }

            LabeledContent("Events recorded", value: "\(entryCount)")
            LabeledContent("In the last 24 hours", value: "\(recentEntryCount)")

            if let diagnosticsMessage {
                InlineNotice(kind: diagnosticsMessage.kind, text: diagnosticsMessage.text)
            }

            HStack {
                Button("Capture TV Details", action: captureDeviceDetails)
                    .disabled(!controller.connectionState.isConnected || isCapturingDeviceDetails)
                Button("Save to Desktop", action: exportToDesktop)
                    .disabled(entryCount == 0)
                Button("Copy", action: copyToClipboard)
                    .disabled(entryCount == 0)
            }
            Button("Clear Log…", role: .destructive) {
                showingClearLogsConfirmation = true
            }
            .disabled(entryCount == 0)
        } header: {
            Text("Diagnostics")
        } footer: {
            SectionFooter("Without “routine events” only warnings and errors are kept. Recording stops when the app quits. The log contains the TV's IP address and settings, and shell command output, but never passwords or keys.")
        }
    }

    private func loadDiagnosticState() {
        isLoggingEnabled = controller.diagnosticLogger.isEnabled
        isDebugMode = controller.diagnosticLogger.isDebugMode
        updateCounts()
    }

    private func updateCounts() {
        entryCount = controller.diagnosticLogger.entryCount
        recentEntryCount = controller.diagnosticLogger.recentEntryCount
    }

    private func exportToDesktop() {
        do {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd-HHmmss"
            let filename = "lgtv-diagnostics-\(formatter.string(from: Date())).json"
            guard let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first else {
                diagnosticsMessage = (.failure, "The Desktop folder could not be found.")
                return
            }
            try controller.diagnosticLogger.exportJSON().write(to: desktopURL.appendingPathComponent(filename), options: .atomic)
            diagnosticsMessage = (.success, "Saved \(filename) to the Desktop.")
        } catch {
            diagnosticsMessage = (.failure, "The log could not be saved: \(error.localizedDescription)")
        }
    }

    private func copyToClipboard() {
        do {
            guard let json = String(data: try controller.diagnosticLogger.exportJSON(), encoding: .utf8) else {
                diagnosticsMessage = (.failure, "The log could not be converted to text.")
                return
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(json, forType: .string)
            diagnosticsMessage = (.success, "Log copied.")
        } catch {
            diagnosticsMessage = (.failure, "The log could not be copied: \(error.localizedDescription)")
        }
    }

    private func captureDeviceDetails() {
        isCapturingDeviceDetails = true
        Task {
            let captured = await controller.gatherDeviceDetails()
            isCapturingDeviceDetails = false
            updateCounts()
            diagnosticsMessage = captured
                ? (.success, "TV details captured. Save or copy the log to share them.")
                : (.failure, "Connect to the TV first.")
        }
    }
}
