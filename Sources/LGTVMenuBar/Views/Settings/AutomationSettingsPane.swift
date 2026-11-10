import SwiftUI

/// What the app does on its own when the Mac sleeps, wakes or the menu is opened.
struct AutomationSettingsPane: View {
    let controller: TVController

    var body: some View {
        Form {
            if controller.configuration == nil {
                Section {
                    InlineNotice(kind: .info, text: "Add your TV in the TV pane to set up automation.")
                }
            } else {
                if !controller.suspendedAutomation.isEmpty {
                    suspendedSection
                }
                powerSection
                inputSection
                wakeOnLANSection
            }
        }
        .formStyle(.grouped)
    }

    private var suspendedSection: some View {
        Section {
            InlineNotice(
                kind: .warning,
                text: "Paused after too many repeats in ten minutes: \(controller.suspendedAutomation.map(\.displayName).joined(separator: ", ")). It resumes by itself in about fifteen minutes."
            )
            Button("Resume Now") {
                controller.resetSuspendedAutomation()
            }
        } header: {
            Text("Paused")
        } footer: {
            SectionFooter("This guard stops the app from switching the TV on and off, or flipping inputs, in a loop. If it keeps tripping, export the diagnostic log from the Advanced pane.")
        }
    }

    private var powerSection: some View {
        Section {
            Toggle("Connect when the app opens", isOn: controller.configurationBinding(\.autoConnectOnLaunch, default: true))
            Toggle("Turn the TV on when the Mac wakes", isOn: controller.configurationBinding(\.wakeWithMac, default: true))
            Toggle("Also when opening the menu", isOn: controller.configurationBinding(\.wakeOnMenuOpen, default: true))
                .disabled(controller.configuration?.wakeWithMac != true)
                .padding(.leading, 20)
            Toggle("Turn the TV off when the Mac sleeps", isOn: controller.configurationBinding(\.sleepWithMac, default: true))
        } header: {
            Text("Power")
        } footer: {
            SectionFooter("The TV is only turned off while it shows the Mac's input. If someone is watching another input or a TV app, it is left on.")
        }
    }

    private var inputSection: some View {
        Section {
            Toggle("Switch to the Mac's input after turning the TV on", isOn: controller.configurationBinding(\.switchInputOnWake, default: false))
            Toggle("Label the Mac's input as a PC", isOn: controller.configurationBinding(\.enablePCMode, default: false))
        } header: {
            Text("Input")
        } footer: {
            SectionFooter("The input is never switched on a TV that was already on. The PC label makes the TV show full-colour text without sharpening and with lower delay.")
        }
    }

    private var wakeOnLANSection: some View {
        Section {
            CommittedTextField(
                title: "Broadcast address",
                prompt: "Automatic",
                value: controller.configuration?.wakeBroadcastAddress ?? "",
                validate: InputValidation.optionalHost
            ) { value in
                update { $0.wakeBroadcastAddress = value.isEmpty ? nil : value }
            }
            CommittedTextField(
                title: "Port",
                prompt: "9 and 7",
                value: controller.configuration?.wakePort.map(String.init) ?? "",
                validate: InputValidation.optionalPort
            ) { value in
                update { $0.wakePort = Int(value) }
            }
            CommittedTextField(
                title: "Give up after (seconds)",
                prompt: "90",
                value: controller.configuration?.wakeTimeoutSeconds.map { String(Int($0)) } ?? "",
                validate: { InputValidation.optionalSeconds($0, range: 10...600) }
            ) { value in
                update { $0.wakeTimeoutSeconds = Double(value) }
            }
        } header: {
            Text("Wake-on-LAN")
        } footer: {
            SectionFooter("Leave these empty unless the TV does not wake. The TV needs “Turn on via Wi-Fi” or “On with Mobile” enabled, and cannot be woken once it is unplugged or in deep standby.")
        }
    }

    private func update(_ mutate: (inout TVConfiguration) -> Void) {
        do {
            try controller.updateConfiguration(mutate)
        } catch {
            controller.diagnosticLogger.log(level: "error", category: "Settings", message: "Could not save automation setting", metadata: ["error": error.localizedDescription])
        }
    }
}
