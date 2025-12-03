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
    @Environment(\.dismiss) private var dismiss
    
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
        .padding(.vertical, 16)
    }
    
    // MARK: - Steps
    
    private var welcomeStep: some View {
        VStack(spacing: 24) {
            // App icon
            Image(systemName: "tv.fill")
                .font(.system(size: 80))
                .foregroundStyle(.blue)
            
            Text("Welcome to LGTV Menu Bar")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            VStack(alignment: .leading, spacing: 12) {
                featureRow(icon: "power", text: "Control your LG TV from the menu bar")
                featureRow(icon: "speaker.wave.2", text: "Adjust volume and switch inputs")
                featureRow(icon: "moon.stars", text: "Auto wake/sleep with your Mac")
                featureRow(icon: "keyboard", text: "Use keyboard volume keys for TV")
            }
            .padding(.horizontal, 32)
            
            Text("Let's set up your TV in a few simple steps")
                .foregroundStyle(.secondary)
                .padding(.top, 8)
        }
    }
    
    private var configurationStep: some View {
        VStack(spacing: 24) {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 60))
                .foregroundStyle(.blue)
            
            Text("Configure Your TV")
                .font(.title)
                .fontWeight(.bold)
            
            VStack(spacing: 16) {
                // TV Name
                VStack(alignment: .leading, spacing: 4) {
                    Text("TV Name")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("e.g., Living Room TV", text: $tvName)
                        .textFieldStyle(.roundedBorder)
                }
                
                // IP Address
                VStack(alignment: .leading, spacing: 4) {
                    Text("IP Address")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("e.g., 192.168.1.100", text: $ipAddress)
                        .textFieldStyle(.roundedBorder)
                    Text("Find this in your TV's Network Settings")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                
                // MAC Address
                VStack(alignment: .leading, spacing: 4) {
                    Text("MAC Address")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("e.g., AA:BB:CC:DD:EE:FF", text: $macAddress)
                        .textFieldStyle(.roundedBorder)
                    Text("Find this in your TV's Network Settings (needed for Wake-on-LAN)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                
                // Preferred Input
                VStack(alignment: .leading, spacing: 4) {
                    Text("Preferred HDMI Input")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("", selection: $preferredInput) {
                        ForEach(TVInputType.allCases, id: \.self) { input in
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
                .foregroundStyle(.blue)
            
            Text("Accept Pairing on TV")
                .font(.title)
                .fontWeight(.bold)
            
            VStack(alignment: .leading, spacing: 16) {
                instructionRow(number: 1, text: "A pairing prompt will appear on your TV screen")
                instructionRow(number: 2, text: "Use your TV remote to select \"Accept\" or \"Allow\"")
                instructionRow(number: 3, text: "The app will connect once you accept the pairing")
            }
            .padding(.horizontal, 32)
            
            if isConnecting {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Waiting for TV pairing...")
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
            
            Text("You're All Set!")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Your TV is now configured and ready to use.")
                    .foregroundStyle(.secondary)
                
                Text("You can:")
                    .fontWeight(.semibold)
                    .padding(.top, 8)
                
                featureRow(icon: "menubar.rectangle", text: "Click the TV icon in your menu bar")
                featureRow(icon: "gearshape", text: "Access settings to customize automation")
                featureRow(icon: "power", text: "Control your TV from anywhere on your Mac")
            }
            .padding(.horizontal, 32)
            
            Button {
                completeOnboarding()
            } label: {
                Text("Get Started")
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
                    Label(nextButtonTitle, systemImage: "chevron.right")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderedProminent)
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
                .foregroundStyle(.blue)
            Text(text)
            Spacer()
        }
    }
    
    private func instructionRow(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.blue))
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
    }
    
    // MARK: - Navigation Logic
    
    private var nextButtonTitle: String {
        switch currentStep {
        case .welcome: return "Get Started"
        case .configuration: return "Connect to TV"
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
        
        withAnimation {
            currentStep = previousStep
            errorMessage = nil
        }
    }
    
    private func goNext() {
        switch currentStep {
        case .welcome:
            withAnimation {
                currentStep = .configuration
            }
            
        case .configuration:
            // Save configuration and attempt connection
            saveAndConnect()
            
        case .instructions:
            if controller.connectionState == .connected {
                withAnimation {
                    currentStep = .success
                }
            }
            
        case .success:
            completeOnboarding()
        }
    }
    
    private func saveAndConnect() {
        errorMessage = nil
        
        let config = TVConfiguration(
            name: tvName,
            ipAddress: ipAddress,
            macAddress: macAddress,
            preferredInput: preferredInput.rawValue,
            wakeWithMac: true,
            sleepWithMac: true,
            switchInputOnWake: false,
            enablePCMode: false
        )
        
        do {
            try controller.saveConfiguration(config)
            
            // Move to instructions step
            withAnimation {
                currentStep = .instructions
            }
            
            // Attempt connection
            isConnecting = true
            Task {
                do {
                    try await controller.connect()
                    await MainActor.run {
                        isConnecting = false
                    }
                } catch {
                    await MainActor.run {
                        isConnecting = false
                        errorMessage = "Connection failed: \(error.localizedDescription)"
                        // Go back to configuration
                        withAnimation {
                            currentStep = .configuration
                        }
                    }
                }
            }
        } catch {
            errorMessage = "Failed to save configuration: \(error.localizedDescription)"
        }
    }
    
    private func skipOnboarding() {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        dismiss()
        onComplete()
    }
    
    private func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        dismiss()
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
