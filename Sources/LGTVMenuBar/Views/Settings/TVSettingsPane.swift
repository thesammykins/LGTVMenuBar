import SwiftUI

/// Which TV to control, and the state of the connection to it.
struct TVSettingsPane: View {
    let controller: TVController

    @State private var newName = ""
    @State private var newAddress = ""
    @State private var newMACAddress = ""
    @State private var setupProblem: String?
    @State private var isConnecting = false
    @State private var connectProblem: String?
    @State private var showingRemoveConfirmation = false

    var body: some View {
        Form {
            if let config = controller.configuration {
                configuredSections(config)
            } else {
                setupSection
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Remove this TV?", isPresented: $showingRemoveConfirmation) {
            Button("Remove TV", role: .destructive, action: removeTV)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The TV's address, automation settings and saved shell credentials are removed from this Mac. The pairing stays on the TV.")
        }
    }

    // MARK: - Configured

    @ViewBuilder
    private func configuredSections(_ config: TVConfiguration) -> some View {
        Section {
            CommittedTextField(title: "Name", prompt: "Living Room TV", value: config.name, validate: InputValidation.tvName) { value in
                update { $0.name = value }
            }
            CommittedTextField(title: "IP address", prompt: "192.168.1.20", value: config.ipAddress, validate: InputValidation.host) { value in
                update { $0.ipAddress = value }
                // The old socket points at the old address.
                controller.resetConnection()
            }
            CommittedTextField(title: "MAC address", prompt: "AA:BB:CC:DD:EE:FF", value: config.macAddress, validate: InputValidation.macAddress) { value in
                update { $0.macAddress = InputValidation.normalizedMACAddress(value) }
            }
            Picker("Mac is connected to", selection: controller.configurationBinding(\.preferredInput, default: "HDMI_1")) {
                ForEach(controller.inputChoices, id: \.input) { choice in
                    Text(choice.title).tag(choice.input.rawValue)
                }
            }
        } header: {
            Text("TV")
        } footer: {
            SectionFooter("The MAC address is used to wake the TV. Both addresses are under Network in the TV's settings; give the TV a fixed IP address on your router so it does not change.")
        }

        Section("Connection") {
            ConnectionStatusView(presentation: controller.connectionPresentation, titleFont: .body)

            if let connectProblem {
                InlineNotice(kind: .failure, text: connectProblem)
            }

            HStack {
                Button(controller.connectionState.isConnected ? "Reconnect" : "Connect", action: connect)
                    .disabled(isConnecting || controller.connectionState.isTransitioning)
                if controller.connectionState.isConnected {
                    Button("Disconnect") { controller.disconnect() }
                }
            }

            if let capabilities = controller.capabilities, controller.connectionState.isConnected {
                if !capabilities.displayModel.isEmpty {
                    LabeledContent("Model", value: capabilities.displayModel)
                }
                if !capabilities.webOSVersion.isEmpty {
                    LabeledContent("Software", value: capabilities.webOSVersion)
                }
                if !capabilities.firmwareVersion.isEmpty {
                    LabeledContent("Firmware", value: capabilities.firmwareVersion)
                }
                LabeledContent("Encryption", value: capabilities.usesSSL ? "Secure WebSocket" : "Not encrypted")
            }
        }

        Section {
            Button("Remove TV…", role: .destructive) {
                showingRemoveConfirmation = true
            }
        }
    }

    // MARK: - Setup

    private var setupSection: some View {
        Section {
            TextField("Name", text: $newName, prompt: Text("Living Room TV"))
            TextField("IP address", text: $newAddress, prompt: Text("192.168.1.20"))
            TextField("MAC address", text: $newMACAddress, prompt: Text("AA:BB:CC:DD:EE:FF"))

            if let setupProblem {
                InlineNotice(kind: .failure, text: setupProblem)
            }

            Button("Add TV", action: addTV)
                .buttonStyle(.borderedProminent)
                .disabled(newName.isEmpty || newAddress.isEmpty || newMACAddress.isEmpty)
        } header: {
            Text("Add a TV")
        } footer: {
            SectionFooter("Both addresses are under Network in the TV's settings. The TV asks you to accept the connection the first time.")
        }
    }

    // MARK: - Actions

    private func update(_ mutate: (inout TVConfiguration) -> Void) {
        do {
            try controller.updateConfiguration(mutate)
        } catch {
            connectProblem = error.localizedDescription
        }
    }

    private func addTV() {
        setupProblem = InputValidation.tvName(newName) ?? InputValidation.host(newAddress) ?? InputValidation.macAddress(newMACAddress)
        guard setupProblem == nil else { return }

        let config = TVConfiguration(
            name: newName.trimmingCharacters(in: .whitespaces),
            ipAddress: newAddress.trimmingCharacters(in: .whitespaces),
            macAddress: InputValidation.normalizedMACAddress(newMACAddress)
        )
        do {
            try controller.saveConfiguration(config)
            UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
            connect()
        } catch {
            setupProblem = error.localizedDescription
        }
    }

    private func connect() {
        connectProblem = nil
        isConnecting = true
        Task {
            defer { isConnecting = false }
            do {
                if controller.connectionState.isConnected {
                    controller.resetConnection()
                }
                try await controller.connect()
            } catch {
                connectProblem = error.localizedDescription
            }
        }
    }

    private func removeTV() {
        if let config = controller.configuration {
            controller.rootAccess.forgetSecrets(for: config)
        }
        controller.disconnect()
        do {
            try controller.clearConfiguration()
        } catch {
            connectProblem = error.localizedDescription
        }
    }
}
