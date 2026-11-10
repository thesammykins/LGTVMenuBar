import SwiftUI

/// The popover shown from the menu bar: status, the controls used every day, and a way into
/// Settings.
///
/// Liquid Glass: the popover itself is the glass surface, supplied by the system on macOS 26
/// and later. Everything inside is content on that surface, so it uses standard controls with
/// no backgrounds or materials of its own. Glass-styled buttons here would stack glass on glass,
/// which the HIG rules out.
struct MenuBarView: View {
    let controller: TVController
    let displayLock: DisplayLockController?
    let onOpenSettings: (SettingsWindowController.Pane?) -> Void

    @State private var actionProblem: String?
    @State private var audioOutputType: AudioOutputType = .unknown
    @State private var audioService = AudioOutputService()

    init(
        controller: TVController,
        displayLock: DisplayLockController? = nil,
        onOpenSettings: @escaping (SettingsWindowController.Pane?) -> Void = { _ in }
    ) {
        self.controller = controller
        self.displayLock = displayLock
        self.onOpenSettings = onOpenSettings
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ConnectionStatusView(presentation: controller.connectionPresentation)

            notices

            Divider()

            if controller.configuration == nil {
                Button("Set Up TV…") { onOpenSettings(.tv) }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Divider()
            } else if controller.connectionState.isConnected {
                ConnectedControls(controller: controller, showsSoundOutput: showsSoundOutput, perform: perform)
                Divider()
                VolumeControls(controller: controller, perform: perform)
                Divider()
            } else {
                if arylicOnly {
                    VolumeControls(controller: controller, perform: perform)
                    Divider()
                }
                DisconnectedControls(controller: controller, report: { actionProblem = $0 })
                Divider()
            }

            HStack {
                Button {
                    onOpenSettings(nil)
                } label: {
                    Label("Settings…", systemImage: "gearshape")
                }
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
            .buttonStyle(.borderless)
        }
        .padding()
        .frame(width: 300)
        .task {
            audioOutputType = audioService.currentOutputType
            audioService.startMonitoring { newType in
                Task { @MainActor in
                    audioOutputType = newType
                }
            }
        }
    }

    @ViewBuilder
    private var notices: some View {
        if let actionProblem {
            HStack(alignment: .top) {
                InlineNotice(kind: .failure, text: actionProblem)
                Spacer(minLength: 4)
                Button {
                    self.actionProblem = nil
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Dismiss")
            }
        }

        if controller.pixelRefreshStartedAt != nil {
            InlineNotice(kind: .info, text: "The TV is off so its pixel refresh can run. It comes back by itself when you return, or in a few minutes.")
        } else if let panelCare = controller.panelCare, panelCare.isRefreshDue, panelCare.shortRefreshOverdueHours >= 24 {
            InlineNotice(kind: .warning, text: "A pixel refresh is \(panelCare.shortRefreshOverdueHours) hours overdue.")
            Button("Review in Settings…") { onOpenSettings(.panelCare) }
                .buttonStyle(.link)
        }

        if !controller.suspendedAutomation.isEmpty {
            InlineNotice(kind: .warning, text: "Some automation is paused to stop a loop.")
            Button("Review in Settings…") { onOpenSettings(.automation) }
                .buttonStyle(.link)
        }

        if case .paused = displayLock?.status {
            InlineNotice(kind: .warning, text: "Display Lock is paused.")
            Button("Review in Settings…") { onOpenSettings(.display) }
                .buttonStyle(.link)
        }
    }

    private var showsSoundOutput: Bool {
        #if LOCAL_ARYLIC_BUILD
        return audioOutputType == .hdmi || controller.volumeControlTarget == .arylic
        #else
        return audioOutputType == .hdmi
        #endif
    }

    private var arylicOnly: Bool {
        #if LOCAL_ARYLIC_BUILD
        return controller.isArylicVolumeControlEnabled && controller.volumeControlTarget == .arylic
        #else
        return false
        #endif
    }

    /// Runs a control's action and shows a failure in the popover instead of an alert.
    private func perform(_ action: @escaping () async throws -> Void) {
        actionProblem = nil
        Task {
            do {
                try await action()
            } catch {
                actionProblem = error.localizedDescription
            }
        }
    }
}

// MARK: - Disconnected

private struct DisconnectedControls: View {
    let controller: TVController
    let report: (String?) -> Void

    @State private var isWaking = false
    @State private var isConnecting = false

    var body: some View {
        HStack(spacing: 8) {
            Button {
                report(nil)
                isWaking = true
                Task {
                    defer { isWaking = false }
                    await controller.ensureTVAwake(reason: "manualWake", requiresWakePreference: false)
                    if !controller.connectionState.isConnected && !controller.connectionState.isTransitioning {
                        report("The TV did not answer after waking it. Check that it has power and that “Turn on via Wi-Fi” is on.")
                    }
                }
            } label: {
                Label("Turn On", systemImage: "power")
                    .frame(maxWidth: .infinity)
            }
            // The one tinted control in this state. On the system's glass popover, emphasis
            // comes from a single coloured background, not from colouring several controls.
            .buttonStyle(.borderedProminent)
            .disabled(isWaking || isConnecting)

            Button {
                report(nil)
                isConnecting = true
                Task {
                    defer { isConnecting = false }
                    do {
                        try await controller.connect()
                    } catch {
                        report(error.localizedDescription)
                    }
                }
            } label: {
                Label("Connect", systemImage: "link")
                    .frame(maxWidth: .infinity)
            }
            .disabled(isWaking || isConnecting || controller.connectionState.isTransitioning)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)

        if isWaking {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Turning the TV on…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Connected

private struct ConnectedControls: View {
    let controller: TVController
    let showsSoundOutput: Bool
    let perform: (@escaping () async throws -> Void) -> Void

    private enum SoundChoice: Hashable {
        case tv(TVSoundOutput)
        case arylic
    }

    var body: some View {
        HStack(spacing: 8) {
            Button {
                perform { try await controller.powerOff() }
            } label: {
                Label("Turn Off", systemImage: "power")
                    .frame(maxWidth: .infinity)
            }
            Button {
                perform { try await controller.screenOff() }
            } label: {
                Label("Screen Off", systemImage: "moon.fill")
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.large)

        Picker("Input", selection: inputBinding) {
            if controller.currentInput == nil {
                Text("TV app").tag(TVInputType?.none)
                Divider()
            }
            ForEach(controller.inputChoices, id: \.input) { choice in
                Text(choice.title).tag(TVInputType?.some(choice.input))
            }
        }

        if showsSoundOutput {
            Picker("Sound", selection: soundBinding) {
                ForEach(soundOutputs, id: \.self) { output in
                    Text(output.displayName).tag(SoundChoice.tv(output))
                }
                #if LOCAL_ARYLIC_BUILD
                if controller.isArylicVolumeControlEnabled {
                    Divider()
                    Text("Arylic").tag(SoundChoice.arylic)
                }
                #endif
            }
        }
    }

    private var inputBinding: Binding<TVInputType?> {
        Binding(
            get: { controller.currentInput },
            set: { newValue in
                guard let newValue, newValue != controller.currentInput else { return }
                perform { try await controller.switchInput(newValue) }
            }
        )
    }

    /// The usual outputs, plus whatever the TV reports if it is something else.
    private var soundOutputs: [TVSoundOutput] {
        var outputs: [TVSoundOutput] = [.tvSpeaker, .externalArc, .externalOptical, .headphone]
        if !outputs.contains(controller.soundOutput) {
            outputs.append(controller.soundOutput)
        }
        return outputs
    }

    private var soundBinding: Binding<SoundChoice> {
        Binding(
            get: {
                #if LOCAL_ARYLIC_BUILD
                if controller.volumeControlTarget == .arylic { return .arylic }
                #endif
                return .tv(controller.soundOutput)
            },
            set: { choice in
                switch choice {
                case .arylic:
                    #if LOCAL_ARYLIC_BUILD
                    controller.volumeControlTarget = .arylic
                    #endif
                case .tv(let output):
                    perform {
                        try await controller.setSoundOutput(output)
                        #if LOCAL_ARYLIC_BUILD
                        controller.volumeControlTarget = .tv
                        #endif
                    }
                }
            }
        )
    }
}

// MARK: - Volume

private struct VolumeControls: View {
    let controller: TVController
    let perform: (@escaping () async throws -> Void) -> Void

    @State private var sliderPosition = 0.5
    @State private var isDragging = false

    var body: some View {
        Group {
            if controller.soundOutput.supportsVolumeSlider || arylicTargeted {
                sliderControl
            } else {
                stepControl
            }
        }
        .onAppear { sliderPosition = VolumeCurve.volumeToSlider(controller.volume) }
        .onChange(of: controller.volume) { _, newValue in
            if !isDragging { sliderPosition = VolumeCurve.volumeToSlider(newValue) }
        }
    }

    private var arylicTargeted: Bool {
        #if LOCAL_ARYLIC_BUILD
        return controller.isArylicVolumeControlEnabled && controller.volumeControlTarget == .arylic
        #else
        return false
        #endif
    }

    private var sliderControl: some View {
        HStack(spacing: 8) {
            muteButton
            Slider(value: $sliderPosition, in: 0...1) {
                Text("Volume")
            } onEditingChanged: { editing in
                isDragging = editing
                if !editing {
                    let volume = VolumeCurve.sliderToVolume(sliderPosition)
                    perform { try await controller.setVolume(volume) }
                }
            }
            .labelsHidden()
            .accessibilityLabel("Volume")
            .accessibilityValue("\(VolumeCurve.sliderToVolume(sliderPosition)) percent")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: perform { try await controller.volumeUp() }
                case .decrement: perform { try await controller.volumeDown() }
                @unknown default: break
                }
            }

            Text("\(VolumeCurve.sliderToVolume(sliderPosition))")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: 28, alignment: .trailing)
                .accessibilityHidden(true)
        }
    }

    /// For ARC and optical the TV does not report a level, so only steps are offered.
    private var stepControl: some View {
        HStack(spacing: 8) {
            Button {
                perform { try await controller.volumeDown() }
            } label: {
                Image(systemName: "speaker.minus.fill").frame(maxWidth: .infinity)
            }
            .help("Volume down")
            .accessibilityLabel("Volume down")

            Button {
                perform { try await controller.toggleMute() }
            } label: {
                Image(systemName: controller.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill").frame(maxWidth: .infinity)
            }
            .help(controller.isMuted ? "Unmute" : "Mute")
            .accessibilityLabel(controller.isMuted ? "Unmute" : "Mute")

            Button {
                perform { try await controller.volumeUp() }
            } label: {
                Image(systemName: "speaker.plus.fill").frame(maxWidth: .infinity)
            }
            .help("Volume up")
            .accessibilityLabel("Volume up")
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }

    private var muteButton: some View {
        Button {
            perform { try await controller.toggleMute() }
        } label: {
            Image(systemName: controller.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.borderless)
        .help(controller.isMuted ? "Unmute" : "Mute")
        .accessibilityLabel(controller.isMuted ? "Unmute" : "Mute")
    }
}
