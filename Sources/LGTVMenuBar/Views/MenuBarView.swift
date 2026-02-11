import SwiftUI

/// Main menu bar popover view displaying TV status and controls
public struct MenuBarView: View {
    @Bindable var controller: TVController
    @State private var showingSettings = false
    @State private var audioOutputType: AudioOutputType = .unknown
    @State private var audioOutputName: String = ""
    @State private var audioService: AudioOutputService?
    
    public init(controller: TVController) {
        self.controller = controller
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Status section
            StatusSection(controller: controller)
            
            Divider()
            
            // Only show controls if connected
            if controller.connectionState.isConnected {
                QuickActionsSection(controller: controller, audioOutputType: audioOutputType)
                Divider()
                VolumeSection(controller: controller)
                Divider()
            } else if controller.configuration != nil {
                ConnectionSection(controller: controller)
                Divider()
            }
            
            // Footer with gear toggle
            FooterSection(showingSettings: $showingSettings)
            
            // Inline settings (when expanded)
            if showingSettings {
                Divider()
                InlineSettingsView(controller: controller)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding()
        .frame(width: showingSettings ? 420 : 280)
        .fixedSize(horizontal: false, vertical: showingSettings)
        .animation(.easeInOut(duration: 0.2), value: showingSettings)
        .conditionalGlassBackground()
        .task {
            // Initialize audio service lazily
            let service = AudioOutputService()
            audioService = service
            
            // Initialize audio output type
            audioOutputType = service.currentOutputType
            audioOutputName = service.currentOutputName
            
            // Start monitoring for changes
            service.startMonitoring { newType in
                Task { @MainActor in
                    audioOutputType = newType
                    audioOutputName = service.currentOutputName
                }
            }
        }
    }
}

// MARK: - Status Section

private struct StatusSection: View {
    @Bindable var controller: TVController
    
    var body: some View {
        HStack {
            // Status indicator
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(controller.configuration?.name ?? "No TV Configured")
                    .font(.headline)
                
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
    }
    
    private var statusColor: Color {
        switch controller.connectionState {
        case .connected: return .green
        case .connecting, .registering: return .orange
        case .disconnected: return .gray
        case .error: return .red
        }
    }
    
    private var statusText: String {
        switch controller.connectionState {
        case .connected:
            if let input = controller.currentInput {
                return input.displayName
            }
            return "Connected"
        case .connecting: return "Connecting..."
        case .registering: return "Pairing..."
        case .disconnected: return "Disconnected"
        case .error: return "Connection Error"
        }
    }
}

// MARK: - Connection Section (when disconnected)

private struct ConnectionSection: View {
    @Bindable var controller: TVController
    @State private var isWaking = false
    @State private var isConnecting = false
    
    var body: some View {
        HStack(spacing: 12) {
            Button {
                Task {
                    isWaking = true
                    defer { isWaking = false }
                    try? await controller.wake()
                }
            } label: {
                Label("Wake TV", systemImage: "power")
            }
            .disabled(isWaking)
            
            Button {
                Task {
                    isConnecting = true
                    defer { isConnecting = false }
                    try? await controller.connect()
                }
            } label: {
                Label("Connect", systemImage: "wifi")
            }
            .disabled(isConnecting)
        }
        .buttonStyle(.bordered)
    }
}

// MARK: - Quick Actions Section

private struct QuickActionsSection: View {
    @Bindable var controller: TVController
    let audioOutputType: AudioOutputType
    
    var body: some View {
        VStack(spacing: 8) {
            // Row 1: Power controls
            HStack(spacing: 12) {
                // Power off button
                Button {
                    Task { try? await controller.powerOff() }
                } label: {
                    Label {
                        Text("Power Off")
                    } icon: {
                        Image(systemName: "power")
                            .imageScale(.medium)
                            .frame(width: 16, height: 16)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 2)
                }
                .buttonStyle(.bordered)
                
                // Screen off button
                Button {
                    Task { try? await controller.screenOff() }
                } label: {
                    Label {
                        Text("Screen Off")
                    } icon: {
                        Image(systemName: "moon.fill")
                            .imageScale(.medium)
                            .frame(width: 16, height: 16)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 2)
                }
                .buttonStyle(.bordered)
            }
            
            // Row 2: Input picker and Sound Output picker (side by side)
            HStack(spacing: 8) {
                // Input picker
                Menu {
                    ForEach(TVInputType.allCases, id: \.self) { input in
                        Button(input.displayName) {
                            Task { try? await controller.switchInput(input) }
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: "tv")
                        Text(controller.currentInput?.displayName ?? "Select Input")
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(.quaternary)
                    .cornerRadius(6)
                }
                .menuStyle(.borderlessButton)
                
                // Sound output picker (only show when Mac audio goes to TV)
                #if LOCAL_ARYLIC_BUILD
                if audioOutputType == .hdmi || controller.volumeControlTarget == .arylic {
                    Menu {
                        Button("TV Speaker") {
                            Task {
                                try? await controller.setSoundOutput(.tvSpeaker)
                                #if LOCAL_ARYLIC_BUILD
                                controller.volumeControlTarget = .tv
                                #endif
                            }
                        }
                        Button("HDMI ARC") {
                            Task {
                                try? await controller.setSoundOutput(.externalArc)
                                #if LOCAL_ARYLIC_BUILD
                                controller.volumeControlTarget = .tv
                                #endif
                            }
                        }
                        Button("Optical") {
                            Task {
                                try? await controller.setSoundOutput(.externalOptical)
                                #if LOCAL_ARYLIC_BUILD
                                controller.volumeControlTarget = .tv
                                #endif
                            }
                        }
                        Button("Headphone") {
                            Task {
                                try? await controller.setSoundOutput(.headphone)
                                #if LOCAL_ARYLIC_BUILD
                                controller.volumeControlTarget = .tv
                                #endif
                            }
                        }
                        #if LOCAL_ARYLIC_BUILD
                        if controller.isArylicVolumeControlEnabled {
                            Divider()
                            Button {
                                controller.volumeControlTarget = .arylic
                            } label: {
                                HStack {
                                    Text("Arylic")
                                    if controller.volumeControlTarget == .arylic {
                                        Spacer()
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                        #endif
                    } label: {
                        HStack {
                            Image(systemName: "speaker.wave.2")
                            #if LOCAL_ARYLIC_BUILD
                            Text(controller.volumeControlTarget == .arylic ? "Arylic" : controller.soundOutput.displayName)
                            #else
                            Text(controller.soundOutput.displayName)
                            #endif
                            Spacer()
                            Image(systemName: "chevron.down")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(.quaternary)
                        .cornerRadius(6)
                    }
                    .menuStyle(.borderlessButton)
                }
                #else
                if audioOutputType == .hdmi {
                    Menu {
                        Button("TV Speaker") {
                            Task { try? await controller.setSoundOutput(.tvSpeaker) }
                        }
                        Button("HDMI ARC") {
                            Task { try? await controller.setSoundOutput(.externalArc) }
                        }
                        Button("Optical") {
                            Task { try? await controller.setSoundOutput(.externalOptical) }
                        }
                        Button("Headphone") {
                            Task { try? await controller.setSoundOutput(.headphone) }
                        }
                    } label: {
                        HStack {
                            Image(systemName: "speaker.wave.2")
                            Text(controller.soundOutput.displayName)
                            Spacer()
                            Image(systemName: "chevron.down")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(.quaternary)
                        .cornerRadius(6)
                    }
                    .menuStyle(.borderlessButton)
                }
                #endif
            }
        }
    }
}

// MARK: - Volume Section

private struct VolumeSection: View {
    @Bindable var controller: TVController
    @State private var sliderPosition: Double = 0.5  // 0-1 range, maps to volume via curve
    
    /// Convert slider position (0-1) to volume (0-100) with power curve
    /// Exponent 2.0 = strong resistance at high volumes
    private func sliderToVolume(_ position: Double) -> Int {
        Int((pow(position, 2.0) * 100).rounded())
    }
    
    /// Convert volume (0-100) to slider position (0-1) - inverse of above
    private func volumeToSlider(_ volume: Int) -> Double {
        pow(Double(volume) / 100.0, 1.0 / 2.0) // sqrt
    }
    
    var body: some View {
        VStack(spacing: 8) {
            // Show different UI based on TV sound output type
            if controller.soundOutput.supportsVolumeSlider {
                // Built-in speakers: show slider with volume level
                sliderVolumeControl
            } else {
                // HDMI/eARC: show simple +/- buttons only
                simpleVolumeControl
            }
        }
        .onChange(of: controller.volume) { _, newValue in
            sliderPosition = volumeToSlider(newValue)
        }
        .onAppear {
            sliderPosition = volumeToSlider(controller.volume)
        }
        .onChange(of: controller.soundOutput) { _, _ in
            sliderPosition = volumeToSlider(controller.volume)
        }
    }
    
    /// Slider-based volume control for built-in speakers
    private var sliderVolumeControl: some View {
        VStack(spacing: 8) {
            HStack {
                // Mute button
                muteButton
                
                // Volume slider
                Slider(value: $sliderPosition, in: 0...1) {
                    Text("Volume")
                } onEditingChanged: { editing in
                    if !editing {
                        Task { try? await controller.setVolume(sliderToVolume(sliderPosition)) }
                    }
                }
                
                // Volume value
                Text("\(sliderToVolume(sliderPosition))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 30)
            }
            
            // Volume up/down buttons for fine control
            HStack {
                volumeDownButton
                Spacer()
                volumeUpButton
            }
        }
    }
    
    /// Simple +/- button volume control for HDMI/eARC output
    private var simpleVolumeControl: some View {
        HStack(spacing: 16) {
            // Volume down
            Button {
                Task { try? await controller.volumeDown() }
            } label: {
                Image(systemName: "speaker.minus.fill")
                    .imageScale(.large)
                    .frame(width: 20, height: 20)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.bordered)
            
            // Mute button (larger, centered)
            Button {
                Task { try? await controller.toggleMute() }
            } label: {
                Image(systemName: controller.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .imageScale(.large)
                    .frame(width: 20, height: 20)
                    .foregroundStyle(controller.isMuted ? .red : .primary)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.bordered)
            
            // Volume up
            Button {
                Task { try? await controller.volumeUp() }
            } label: {
                Image(systemName: "speaker.plus.fill")
                    .imageScale(.large)
                    .frame(width: 20, height: 20)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
    }
    
    private var muteButton: some View {
        Button {
            Task { try? await controller.toggleMute() }
        } label: {
            Image(systemName: controller.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .foregroundStyle(controller.isMuted ? .red : .primary)
        }
        .buttonStyle(.borderless)
    }
    
    private var volumeDownButton: some View {
        Button {
            Task {
                try? await controller.volumeDown()
                // Update slider position based on new volume (linear 1% decrement)
                let currentVolume = sliderToVolume(sliderPosition)
                let newVolume = max(0, currentVolume - 1)
                sliderPosition = volumeToSlider(newVolume)
            }
        } label: {
            Image(systemName: "minus")
        }
        .buttonStyle(.borderless)
    }
    
    private var volumeUpButton: some View {
        Button {
            Task {
                try? await controller.volumeUp()
                // Update slider position based on new volume (linear 1% increment)
                let currentVolume = sliderToVolume(sliderPosition)
                let newVolume = min(100, currentVolume + 1)
                sliderPosition = volumeToSlider(newVolume)
            }
        } label: {
            Image(systemName: "plus")
        }
        .buttonStyle(.borderless)
    }
}

// MARK: - Footer Section

private struct FooterSection: View {
    @Binding var showingSettings: Bool
    
    var body: some View {
        HStack {
            Button {
                showingSettings.toggle()
            } label: {
                Image(systemName: showingSettings ? "gearshape.fill" : "gearshape")
                    .foregroundStyle(showingSettings ? .primary : .secondary)
            }
            .buttonStyle(.borderless)
            .help(showingSettings ? "Hide Settings" : "Show Settings")
            
            Spacer()
            
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("q")
        }
        .font(.caption)
    }
}

// MARK: - Liquid Glass Modifier

extension View {
    /// Applies Liquid Glass background effect on macOS 26+ (Tahoe)
    /// On older versions, returns the view unchanged
    @ViewBuilder
    func conditionalGlassBackground() -> some View {
        if #available(macOS 26, *) {
            // TODO: Replace with actual Liquid Glass API when macOS 26 SDK is available
            // Expected: self.glassBackgroundEffect()
            self.background(.ultraThinMaterial)
        } else {
            // Keep current appearance - no changes for pre-Tahoe
            self
        }
    }
}
