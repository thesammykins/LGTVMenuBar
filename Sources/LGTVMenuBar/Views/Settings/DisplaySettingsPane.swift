import SwiftUI

/// Display Lock: hold the Mac's display mode, HDR and chosen TV settings while the TV shows the
/// Mac's input.
struct DisplaySettingsPane: View {
    let controller: TVController
    let displayLock: DisplayLockController

    @State private var displays: [DisplayInfo] = []
    @State private var modes: [DisplayModeSpec] = []
    @State private var pictureModeProblem: String?
    @State private var isReadingPictureMode = false

    private enum HDRChoice: Hashable { case unchanged, on, off }

    var body: some View {
        Form {
            if controller.configuration == nil {
                Section {
                    InlineNotice(kind: .info, text: "Add your TV in the TV pane to use Display Lock.")
                }
            } else {
                lockSection
                macSection
                tvSection
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: reloadDisplays)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            reloadDisplays()
        }
        .onChange(of: profile.displayUUID) { _, _ in
            reloadDisplays()
        }
    }

    private var profile: DisplayLockProfile {
        controller.configuration?.displayLock ?? DisplayLockProfile()
    }

    private var targetDisplay: DisplayInfo? {
        DisplayLockEvaluator.resolveDisplay(profile: profile, displays: displays)
    }

    // MARK: - Sections

    private var lockSection: some View {
        Section {
            Toggle("Lock display settings", isOn: controller.configurationBinding(\.displayLock.isEnabled, default: false))

            statusRow

            Picker("While the TV shows", selection: controller.configurationBinding(\.displayLock.inputID, default: "")) {
                Text("The Mac's input").tag("")
                Divider()
                ForEach(controller.inputChoices, id: \.input) { choice in
                    Text(choice.title).tag(choice.input.rawValue)
                }
            }

            Picker("Display", selection: controller.configurationBinding(\.displayLock.displayUUID, default: nil)) {
                Text("Detect the LG TV").tag(String?.none)
                Divider()
                ForEach(displays) { display in
                    Text(display.name).tag(String?.some(display.uuid))
                }
            }
        } footer: {
            SectionFooter("The settings below are put back whenever they change while the TV shows that input. On any other input or TV app, nothing is touched.")
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch displayLock.status {
        case .off:
            EmptyView()
        case .inactive(let reason):
            InlineNotice(kind: .info, text: "Not active: \(reason).")
        case .checking:
            InlineNotice(kind: .info, text: "Checking…")
        case .compliant:
            InlineNotice(kind: .success, text: "Everything matches.")
        case .applying(let what):
            InlineNotice(kind: .info, text: "Setting \(what)…")
        case .paused(let message):
            InlineNotice(kind: .warning, text: message)
            Button("Resume") {
                displayLock.resume()
            }
        }
    }

    private var macSection: some View {
        Section {
            if let display = targetDisplay {
                Picker("Resolution and refresh rate", selection: controller.configurationBinding(\.displayLock.mode, default: nil)) {
                    Text("Don’t change").tag(DisplayModeSpec?.none)
                    Divider()
                    ForEach(modeChoices, id: \.self) { mode in
                        Text(mode.displayName).tag(DisplayModeSpec?.some(mode))
                    }
                }

                Picker("HDR", selection: hdrBinding) {
                    Text("Don’t change").tag(HDRChoice.unchanged)
                    Text("On").tag(HDRChoice.on)
                    Text("Off").tag(HDRChoice.off)
                }
                .disabled(!displayLock.canControlHDR || !display.hdrSupported)

                LabeledContent("Now") {
                    Text(currentDescription(display))
                        .foregroundStyle(.secondary)
                }

                Button("Use Current Settings") {
                    update {
                        $0.displayLock.mode = display.currentMode
                        if displayLock.canControlHDR && display.hdrSupported {
                            $0.displayLock.hdrEnabled = display.hdrEnabled
                        }
                    }
                }
            } else {
                InlineNotice(kind: .info, text: displays.contains(where: \.isLG) ? "More than one LG display is attached. Choose which one is the TV above." : "The TV is not attached to this Mac as a display.")
            }
        } header: {
            Text("On This Mac")
        } footer: {
            if !displayLock.canControlHDR {
                SectionFooter("This version of macOS does not let apps switch HDR, so HDR cannot be locked.")
            } else {
                SectionFooter("Changing these makes the picture blink for a moment, the same as changing them in System Settings.")
            }
        }
    }

    private var tvSection: some View {
        Section {
            Toggle("Keep the input labelled as a PC", isOn: controller.configurationBinding(\.displayLock.enforcePCMode, default: false))

            CommittedTextField(
                title: "Picture mode",
                prompt: "Don’t change",
                value: profile.pictureMode ?? ""
            ) { value in
                update { $0.displayLock.pictureMode = value.isEmpty ? nil : value }
            }

            HStack {
                Button("Use the TV’s Current Mode", action: readPictureMode)
                    .disabled(!controller.connectionState.isConnected || isReadingPictureMode)
                if isReadingPictureMode {
                    ProgressView().controlSize(.small)
                }
            }

            if let pictureModeProblem {
                InlineNotice(kind: .failure, text: pictureModeProblem)
            }
        } header: {
            Text("On the TV")
        } footer: {
            SectionFooter("The TV keeps a separate picture mode for standard, HDR and Dolby Vision video. The mode named here is applied to whichever is playing, so set it while the TV shows the kind of picture you normally use.")
        }
    }

    // MARK: - Helpers

    /// Modes on offer, always including the saved one even if it is not available right now.
    private var modeChoices: [DisplayModeSpec] {
        guard let saved = profile.mode, !modes.contains(where: { $0.matches(saved) }) else { return modes }
        return [saved] + modes
    }

    private var hdrBinding: Binding<HDRChoice> {
        Binding(
            get: {
                switch profile.hdrEnabled {
                case .none: return .unchanged
                case .some(true): return .on
                case .some(false): return .off
                }
            },
            set: { choice in
                update {
                    switch choice {
                    case .unchanged: $0.displayLock.hdrEnabled = nil
                    case .on: $0.displayLock.hdrEnabled = true
                    case .off: $0.displayLock.hdrEnabled = false
                    }
                }
            }
        )
    }

    private func currentDescription(_ display: DisplayInfo) -> String {
        let mode = display.currentMode?.displayName ?? "Unknown mode"
        guard display.hdrSupported else { return mode }
        return "\(mode), HDR \(display.hdrEnabled ? "on" : "off")"
    }

    private func reloadDisplays() {
        displays = displayLock.displays
        modes = targetDisplay.map { displayLock.availableModes(forDisplayUUID: $0.uuid) } ?? []
    }

    private func update(_ mutate: (inout TVConfiguration) -> Void) {
        do {
            try controller.updateConfiguration(mutate)
        } catch {
            pictureModeProblem = error.localizedDescription
        }
    }

    private func readPictureMode() {
        pictureModeProblem = nil
        isReadingPictureMode = true
        Task {
            defer { isReadingPictureMode = false }
            do {
                let mode = try await controller.readPictureMode()
                update { $0.displayLock.pictureMode = mode }
            } catch {
                pictureModeProblem = "Could not read the picture mode: \(error.localizedDescription)"
            }
        }
    }
}
