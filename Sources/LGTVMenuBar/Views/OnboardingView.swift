import SwiftUI

/// First-run onboarding wizard for TV setup
/// Displayed as a standalone window on initial launch
struct OnboardingView: View {
    @Bindable var controller: TVController
    let onComplete: () -> Void
    
    @State private var currentStep: OnboardingStep = .welcome
    @State private var tvName: String = ""
    @State private var ipAddress: String = ""
    @State private var macAddress: String = ""
    @State private var preferredInput: TVInputType = .hdmi1
    @State private var isConnecting: Bool = false
    @State private var errorMessage: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    var body: some View {
        VStack(spacing: 0) {
            // Progress indicator
            progressIndicator
            
            Divider()
            
            // Content area
            ScrollView {
                VStack(spacing: 24) {
                    switch currentStep {
                    case .welcome:
                        welcomeStep
                    case .configuration:
                        configurationStep
                    case .instructions:
                        instructionsStep
                    case .success:
                        successStep
                    }
                }
                .padding(32)
                .frame(maxWidth: .infinity)
            }
            
            Divider()
            
            // Navigation buttons
            navigationButtons
        }
        .frame(width: 500, height: 600)
    }
    
    // MARK: - Progress Indicator
    
    private var progressIndicator: some View {
        HStack(spacing: 8) {
            ForEach(OnboardingStep.allCases, id: \.self) { step in
                Circle()
                    .fill(step.rawValue <= currentStep.rawValue ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 10, height: 10)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(currentStep.rawValue + 1) of \(OnboardingStep.allCases.count)")
        .padding(.vertical, 16)
    }
    
    // MARK: - Steps
    
    private var welcomeStep: some View {
        VStack(spacing: 24) {
            // App icon
            Image(systemName: "tv.fill")
                .font(.system(size: 80))
                .foregroundStyle(Color.accentColor)
            
            Text("Welcome to LGTV Menu Bar")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            VStack(alignment: .leading, spacing: 12) {
                featureRow(icon: "power", text: "Control your LG TV from the menu bar")
                featureRow(icon: "speaker.wave.2", text: "Adjust volume and switch inputs")
                featureRow(icon: "moon.stars", text: "Turn the TV on and off with your Mac")
                featureRow(icon: "keyboard", text: "Use keyboard volume keys for TV")
            }
            .padding(.horizontal, 32)
            
            Text("Setting up takes about a minute.")
                .foregroundStyle(.secondary)
                .padding(.top, 8)
        }
    }
    
    private var configurationStep: some View {
        VStack(spacing: 24) {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 60))
                .foregroundStyle(Color.accentColor)
            
            Text("Configure Your TV")
                .font(.title)
                .fontWeight(.bold)
            
            VStack(spacing: 16) {
                // TV Name
                VStack(alignment: .leading, spacing: 4) {
                    Text("TV Name")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("TV Name", text: $tvName, prompt: Text("Living Room TV"))
                        .textFieldStyle(.roundedBorder)
                }
                
                // IP Address
                VStack(alignment: .leading, spacing: 4) {
                    Text("IP Address")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("IP Address", text: $ipAddress, prompt: Text("192.168.1.20"))
                        .textFieldStyle(.roundedBorder)
                    Text("Under Network in the TV's settings.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                
                // MAC Address
                VStack(alignment: .leading, spacing: 4) {
                    Text("MAC Address")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("MAC Address", text: $macAddress, prompt: Text("AA:BB:CC:DD:EE:FF"))
                        .textFieldStyle(.roundedBorder)
                    Text("Also under Network in the TV's settings. It is used to turn the TV on.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                
                // Preferred Input
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mac Is Connected To")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Mac is connected to", selection: $preferredInput) {
                        ForEach([TVInputType.hdmi1, .hdmi2, .hdmi3, .hdmi4], id: \.self) { input in
                            Text(input.displayName).tag(input)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
            }
            .padding(.horizontal, 32)
            
            if let error = errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(.horizontal, 32)
            }
        }
    }
    
    private var instructionsStep: some View {
        VStack(spacing: 24) {
            Image(systemName: "hand.tap.fill")
                .font(.system(size: 60))
                .foregroundStyle(Color.accentColor)
            
            Text("Accept the Prompt on Your TV")
                .font(.title)
                .fontWeight(.bold)
            
            VStack(alignment: .leading, spacing: 16) {
                instructionRow(number: 1, text: "The TV shows a prompt asking whether to allow this Mac.")
                instructionRow(number: 2, text: "Choose Accept with the TV remote. You have about a minute.")
                instructionRow(number: 3, text: "Setup continues by itself once the TV accepts.")
            }
            .padding(.horizontal, 32)
            
            if isConnecting {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text(controller.connectionState == .awaitingPairing ? "Waiting for you to accept on the TV…" : "Contacting the TV…")
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 16)
            }
            
            if controller.connectionState == .connected {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Successfully connected!")
                        .foregroundStyle(.green)
                }
                .padding(.top, 16)
            }
        }
    }
    
    private var successStep: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.green)
            
            Text("Your TV Is Ready")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            VStack(alignment: .leading, spacing: 12) {
                featureRow(icon: "menubar.rectangle", text: "Click the TV icon in the menu bar for power, input and volume.")
                featureRow(icon: "gearshape", text: "Open Settings from there to choose what happens when your Mac sleeps and wakes.")
            }
            .padding(.horizontal, 32)
            
            Button {
                completeOnboarding()
            } label: {
                Text("Done")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 32)
            .padding(.top, 16)
        }
    }
    
    // MARK: - Navigation Buttons
    
    private var navigationButtons: some View {
        HStack {
            // Back button
            if currentStep != .welcome {
                Button {
                    goBack()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.borderless)
            }
            
            Spacer()
            
            // Skip button (only on early steps)
            if currentStep != .success {
                Button("Skip Setup") {
                    skipOnboarding()
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
            
            // Next/Connect button
            if currentStep != .success {
                Button {
                    goNext()
                } label: {
                    Text(nextButtonTitle)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canProceed)
            }
        }
        .padding(16)
    }
    
    // MARK: - Helper Views
    
    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(Color.accentColor)
            Text(text)
            Spacer()
        }
    }
    
    private func instructionRow(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(Color.accentColor)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.accentColor.opacity(0.15)))
                .accessibilityHidden(true)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
    }
    
    // MARK: - Navigation Logic
    
    private var nextButtonTitle: String {
        switch currentStep {
        case .welcome: return "Continue"
        case .configuration: return "Connect"
        case .instructions: return "Continue"
        case .success: return ""
        }
    }
    
    private var canProceed: Bool {
        switch currentStep {
        case .welcome:
            return true
        case .configuration:
            return !tvName.isEmpty && !ipAddress.isEmpty && !macAddress.isEmpty && !isConnecting
        case .instructions:
            return controller.connectionState == .connected
        case .success:
            return true
        }
    }
    
    private func goBack() {
        guard let previousStep = OnboardingStep(rawValue: currentStep.rawValue - 1) else {
            return
        }

        // Leaving the pairing step abandons the attempt, so the TV's prompt does not linger.
        if currentStep == .instructions && !controller.connectionState.isConnected {
            controller.disconnect()
            isConnecting = false
        }

        move(to: previousStep)
        errorMessage = nil
    }
    
    private func goNext() {
        switch currentStep {
        case .welcome:
            move(to: .configuration)
            
        case .configuration:
            // Save configuration and attempt connection
            saveAndConnect()
            
        case .instructions:
            if controller.connectionState == .connected {
                move(to: .success)
            }
            
        case .success:
            completeOnboarding()
        }
    }
    
    /// Step changes animate unless the user has asked macOS to reduce motion.
    private func move(to step: OnboardingStep) {
        if reduceMotion {
            currentStep = step
        } else {
            withAnimation { currentStep = step }
        }
    }

    private func saveAndConnect() {
        errorMessage = InputValidation.tvName(tvName) ?? InputValidation.host(ipAddress) ?? InputValidation.macAddress(macAddress)
        guard errorMessage == nil else { return }
        
        let config = TVConfiguration(
            name: tvName.trimmingCharacters(in: .whitespaces),
            ipAddress: ipAddress.trimmingCharacters(in: .whitespaces),
            macAddress: InputValidation.normalizedMACAddress(macAddress),
            preferredInput: preferredInput.rawValue,
            wakeWithMac: true,
            sleepWithMac: true,
            switchInputOnWake: false,
            enablePCMode: false
        )
        
        do {
            try controller.saveConfiguration(config)
            
            move(to: .instructions)

            isConnecting = true
            Task {
                defer { isConnecting = false }
                do {
                    try await controller.connect()
                    if currentStep == .instructions {
                        move(to: .success)
                    }
                } catch {
                    // Back was pressed: the attempt was abandoned on purpose.
                    guard currentStep == .instructions else { return }
                    errorMessage = error.localizedDescription
                    move(to: .configuration)
                }
            }
        } catch {
            errorMessage = "Failed to save configuration: \(error.localizedDescription)"
        }
    }
    
    private func skipOnboarding() {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        onComplete()
    }
    
    private func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        onComplete()
    }
}

// MARK: - Onboarding Step Enum

private enum OnboardingStep: Int, CaseIterable {
    case welcome = 0
    case configuration = 1
    case instructions = 2
    case success = 3
}
