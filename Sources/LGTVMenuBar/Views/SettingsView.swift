import SwiftUI
import AppKit

/// Settings content designed for inline display in menu bar popover
struct InlineSettingsView: View {
    @Bindable var controller: TVController
    
    var body: some View {
        TabView {
            TVConfigurationTab(controller: controller)
                .tabItem {
                    Label("TV", systemImage: "tv")
                }
            
            AutomationTab(controller: controller)
                .tabItem {
                    Label("Automation", systemImage: "gearshape.2")
                }
            
            GeneralTab(controller: controller)
                .tabItem {
                    Label("General", systemImage: "gear")
                }
            
            DiagnosticsTab(controller: controller)
                .tabItem {
                    Label("Diagnostics", systemImage: "bandage")
                }
            
            #if LOCAL_ARYLIC_BUILD
            ArylicTab(controller: controller)
                .tabItem {
                    Label("Arylic", systemImage: "hifispeaker")
                }
            #endif
        }
        .frame(maxHeight: 500)
    }
}

/// Settings view for standalone window (kept for potential future use)
struct SettingsView: View {
    @Bindable var controller: TVController
    
    var body: some View {
        InlineSettingsView(controller: controller)
            .frame(width: 450, height: 350)
    }
}

// MARK: - TV Configuration Tab

struct TVConfigurationTab: View {
    @Bindable var controller: TVController
    
    @State private var name: String = ""
    @State private var ipAddress: String = ""
    @State private var macAddress: String = ""
    @State private var preferredInput: TVInputType = .hdmi1
    @State private var showingSaveConfirmation = false
    @State private var errorMessage: String?
    
    var body: some View {
        Form {
            Section {
                TextField("TV Name", text: $name)
                    .textFieldStyle(.roundedBorder)
                
                TextField("IP Address", text: $ipAddress)
                    .textFieldStyle(.roundedBorder)
                    .help("e.g., 192.168.1.100")
                
                TextField("MAC Address", text: $macAddress)
                    .textFieldStyle(.roundedBorder)
                    .help("e.g., AA:BB:CC:DD:EE:FF")
                
                Picker("Preferred Input", selection: $preferredInput) {
                    ForEach(TVInputType.allCases, id: \.self) { input in
                        Text(input.displayName).tag(input)
                    }
                }
            } header: {
                Text("TV Connection")
            }
            
            Section {
                HStack {
                    // Connection status
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    Text(statusText)
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    // Test connection button
                    Button("Test Connection") {
                        Task {
                            try? await controller.connect()
                        }
                    }
                    .disabled(ipAddress.isEmpty)
                }
            } header: {
                Text("Status")
            }
            
            if let error = errorMessage {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
            
            Section {
                HStack {
                    Button("Save") {
                        saveConfiguration()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(name.isEmpty || ipAddress.isEmpty || macAddress.isEmpty)
                    
                    Button("Clear", role: .destructive) {
                        clearConfiguration()
                    }
                    .disabled(controller.configuration == nil)
                }
            }
        }
        .formStyle(.columns)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .onAppear {
            loadCurrentConfiguration()
        }
        .alert("Configuration Saved", isPresented: $showingSaveConfirmation) {
            Button("OK", role: .cancel) { }
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
        case .connected: return "Connected"
        case .connecting: return "Connecting..."
        case .registering: return "Pairing with TV..."
        case .disconnected: return "Not connected"
        case .error: return "Connection error"
        }
    }
    
    private func loadCurrentConfiguration() {
        if let config = controller.configuration {
            name = config.name
            ipAddress = config.ipAddress
            macAddress = config.macAddress
            preferredInput = TVInputType(rawValue: config.preferredInput) ?? .hdmi1
        }
    }
    
    private func saveConfiguration() {
        let config = TVConfiguration(
            id: controller.configuration?.id ?? UUID(),
            name: name,
            ipAddress: ipAddress,
            macAddress: macAddress,
            preferredInput: preferredInput.rawValue,
            autoConnectOnLaunch: controller.configuration?.autoConnectOnLaunch ?? true,
            wakeWithMac: controller.configuration?.wakeWithMac ?? true,
            sleepWithMac: controller.configuration?.sleepWithMac ?? true,
            switchInputOnWake: controller.configuration?.switchInputOnWake ?? false,
            enablePCMode: controller.configuration?.enablePCMode ?? false
        )
        
        do {
            try controller.saveConfiguration(config)
            errorMessage = nil
            showingSaveConfirmation = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    private func clearConfiguration() {
        do {
            try controller.clearConfiguration()
            name = ""
            ipAddress = ""
            macAddress = ""
            preferredInput = .hdmi1
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Automation Tab

struct AutomationTab: View {
    @Bindable var controller: TVController
    
    @State private var autoConnectOnLaunch: Bool = true
    @State private var wakeWithMac: Bool = true
    @State private var sleepWithMac: Bool = true
    @State private var switchInputOnWake: Bool = false
    @State private var enablePCMode: Bool = false
    
    var body: some View {
        Form {
            Section {
                Toggle("Connect to TV on app launch", isOn: $autoConnectOnLaunch)
                    .help("Automatically connect to your TV when the app starts")
                
                Toggle("Wake TV when Mac wakes", isOn: $wakeWithMac)
                    .help("Automatically send Wake-on-LAN when your Mac wakes from sleep")
                
                Toggle("Sleep TV when Mac sleeps", isOn: $sleepWithMac)
                    .help("Automatically turn off TV when your Mac goes to sleep")
            } header: {
                Text("Power Sync")
            }
            
            Section {
                Toggle("Switch to preferred input on wake", isOn: $switchInputOnWake)
                    .help("After waking the TV, automatically switch to your preferred HDMI input")
                
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Enable PC Mode", isOn: $enablePCMode)
                        .help("Set the TV input to PC mode for better display with your Mac")
                    
                    Text("Recommended for best display quality when using Mac")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Input Settings")
            }
            
            Section {
                Button("Save Changes") {
                    saveAutomationSettings()
                }
                .buttonStyle(.borderedProminent)
                .disabled(controller.configuration == nil)
            }
        }
        .formStyle(.columns)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .onAppear {
            loadAutomationSettings()
        }
    }
    
    private func loadAutomationSettings() {
        if let config = controller.configuration {
            autoConnectOnLaunch = config.autoConnectOnLaunch
            wakeWithMac = config.wakeWithMac
            sleepWithMac = config.sleepWithMac
            switchInputOnWake = config.switchInputOnWake
            enablePCMode = config.enablePCMode
        }
    }
    
    private func saveAutomationSettings() {
        guard let existing = controller.configuration else { return }
        
        let updated = TVConfiguration(
            id: existing.id,
            name: existing.name,
            ipAddress: existing.ipAddress,
            macAddress: existing.macAddress,
            preferredInput: existing.preferredInput,
            autoConnectOnLaunch: autoConnectOnLaunch,
            wakeWithMac: wakeWithMac,
            sleepWithMac: sleepWithMac,
            switchInputOnWake: switchInputOnWake,
            enablePCMode: enablePCMode
        )
        
        try? controller.saveConfiguration(updated)
    }
}

// MARK: - General Tab

struct GeneralTab: View {
    @Bindable var controller: TVController
    
    @State private var launchAtLogin: Bool = false
    @State private var mediaKeysEnabled: Bool = false
    @State private var hasAccessibilityPermission: Bool = false
    @State private var permissionCheckTimer: Timer?
    
    /// App version from bundle, with fallback
    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }
    
    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .help("Automatically start LGTV Menu Bar when you log in")
                    .onChange(of: launchAtLogin) { _, newValue in
                        Task {
                            try? await controller.setLaunchAtLogin(newValue)
                        }
                    }
            } header: {
                Text("Startup")
            }
            
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Toggle("Use keyboard volume keys for TV", isOn: $mediaKeysEnabled)
                            .disabled(!hasAccessibilityPermission)
                            .onChange(of: mediaKeysEnabled) { _, newValue in
                                controller.isMediaKeyControlEnabled = newValue
                            }
                        
                        // Permission status indicator
                        Circle()
                            .fill(hasAccessibilityPermission ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                            .help(hasAccessibilityPermission ? "Accessibility permission granted" : "Accessibility permission required")
                    }
                    
                    // Status message based on state
                    Group {
                        if !hasAccessibilityPermission {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                Text("Accessibility permission required")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("Grant Access") {
                                    requestAccessibilityPermission()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            Text("If already granted, remove LGTV Menu Bar from Accessibility and re-add it.")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        } else if mediaKeysEnabled {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text(controller.connectionState.isConnected 
                                    ? "Volume keys controlling TV" 
                                    : "Will activate when TV connects")
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Text("Enable to control TV volume with keyboard keys")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.caption)
                }
                
                #if LOCAL_ARYLIC_BUILD
                Toggle("Route volume to Arylic device", isOn: Binding(
                    get: { controller.isArylicVolumeControlEnabled },
                    set: { controller.isArylicVolumeControlEnabled = $0 }
                ))
                .help("When enabled, volume keys control an Arylic device instead of the TV")
                #endif
            } header: {
                Text("Volume Control")
            }
            
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("LGTV Menu Bar")
                        .font(.headline)
                    Text("Version \(appVersion)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("About")
            }
        }
        .formStyle(.columns)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .task {
            launchAtLogin = (try? await controller.isLaunchAtLoginEnabled()) ?? false
            mediaKeysEnabled = controller.isMediaKeyControlEnabled
            checkAccessibilityPermission()
            startPermissionPollingIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Re-check permission when app becomes active (user may have just granted it)
            checkAccessibilityPermission()
        }
        .onAppear {
            startPermissionPollingIfNeeded()
        }
        .onDisappear {
            stopPermissionPolling()
        }
    }
    
    private func checkAccessibilityPermission() {
        let wasGranted = hasAccessibilityPermission
        hasAccessibilityPermission = controller.hasAccessibilityPermission()

        if !hasAccessibilityPermission && controller.isMediaKeyControlEnabled {
            controller.isMediaKeyControlEnabled = false
            mediaKeysEnabled = false
        }
        
        // If just granted, stop polling and reinitialize media key capture
        if !wasGranted && hasAccessibilityPermission {
            stopPermissionPolling()
            
            // If media keys were already enabled (user toggled before permission was granted),
            // or if user had previously enabled them, trigger a re-initialization
            if controller.isMediaKeyControlEnabled {
                Task {
                    // Brief delay to let macOS fully activate the permission
                    try? await Task.sleep(for: .milliseconds(500))
                    // Toggle off and on to force re-initialization of event tap
                    controller.isMediaKeyControlEnabled = false
                    try? await Task.sleep(for: .milliseconds(100))
                    controller.isMediaKeyControlEnabled = true
                    mediaKeysEnabled = true
                }
            }
        }
    }
    
    private func startPermissionPollingIfNeeded() {
        guard !hasAccessibilityPermission else { return }
        stopPermissionPolling() // Clear any existing timer
        
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
            Task { @MainActor in
                checkAccessibilityPermission()
                if hasAccessibilityPermission {
                    stopPermissionPolling()
                }
            }
        }
    }
    
    private func stopPermissionPolling() {
        permissionCheckTimer?.invalidate()
        permissionCheckTimer = nil
    }
    
    private func openAccessibilitySettings() {
        // Open System Settings to Accessibility pane
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func requestAccessibilityPermission() {
        let granted = controller.requestAccessibilityPermission()
        if !granted {
            openAccessibilitySettings()
        }
        checkAccessibilityPermission()
        startPermissionPollingIfNeeded()
        if hasAccessibilityPermission {
            controller.refreshMediaKeyCapture()
        }
    }
}

// MARK: - Diagnostics Tab

struct DiagnosticsTab: View {
    let controller: TVController
    
    @State private var isLoggingEnabled: Bool = false
    @State private var isDebugMode: Bool = false
    @State private var entryCount: Int = 0
    @State private var recentEntryCount: Int = 0
    @State private var showingExportSuccess = false
    @State private var showingClipboardSuccess = false
    @State private var showingError = false
    @State private var errorMessage: String = ""
    @State private var showingDeviceDetailsSuccess = false
    @State private var isCapturingDeviceDetails = false
    
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Enable Diagnostic Logging", isOn: $isLoggingEnabled)
                        .onChange(of: isLoggingEnabled) { _, newValue in
                            controller.setDiagnosticLoggingEnabled(newValue)
                            updateCounts()
                        }
                    
                    Text("⚠️ Logging state resets on app restart")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                if isLoggingEnabled {
                    Toggle("Enable Debug Mode", isOn: $isDebugMode)
                        .help("Captures all log levels (debug, info, warning, error)")
                        .onChange(of: isDebugMode) { _, newValue in
                            controller.setDiagnosticDebugMode(newValue)
                        }
                }
            } header: {
                Text("Capture Settings")
            }
            
            Section {
                HStack {
                    Text("Events Captured:")
                    Spacer()
                    Text("\(entryCount)")
                        .foregroundStyle(.secondary)
                }
                
                HStack {
                    Text("Last 24 Hours:")
                    Spacer()
                    Text("\(recentEntryCount)")
                        .foregroundStyle(.secondary)
                }
                
                HStack {
                    Text("Capturing:")
                    Spacer()
                    Text(isDebugMode ? "All Levels" : "Warnings & Errors")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Status")
            }
            
            Section {
                Button("Gather Device Details") {
                    captureDeviceDetails()
                }
                .disabled(!controller.connectionState.isConnected || isCapturingDeviceDetails)
                .help("Captures raw TV payloads for input and sound output diagnosis")

                Button("Export Logs to Desktop") {
                    exportToDesktop()
                }
                .disabled(entryCount == 0)
                
                Button("Copy to Clipboard") {
                    copyToClipboard()
                }
                .disabled(entryCount == 0)
                
                Button("Clear Logs", role: .destructive) {
                    controller.diagnosticLogger.clear()
                    updateCounts()
                }
                .disabled(entryCount == 0)
            } header: {
                Text("Actions")
            }
            
            Section {
                Label {
                    Text("Logs may contain IP addresses and configuration details")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Privacy Notice")
            }
        }
        .formStyle(.columns)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .onAppear {
            loadDiagnosticState()
        }
        .alert("Export Successful", isPresented: $showingExportSuccess) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Diagnostic logs saved to Desktop")
        }
        .alert("Copied to Clipboard", isPresented: $showingClipboardSuccess) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Diagnostic logs copied as JSON")
        }
        .alert("Device Details Captured", isPresented: $showingDeviceDetailsSuccess) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Device details captured. Export logs to share the payload.")
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
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
            // Create filename with timestamp: lgtv-diagnostics-YYYY-MM-DD-HHmmss.json
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd-HHmmss"
            let timestamp = formatter.string(from: Date())
            let filename = "lgtv-diagnostics-\(timestamp).json"
            
            // Get Desktop URL
            guard let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first else {
                errorMessage = "Could not locate Desktop directory"
                showingError = true
                return
            }
            
            let fileURL = desktopURL.appendingPathComponent(filename)
            
            // Export and write
            let jsonData = try controller.diagnosticLogger.exportJSON()
            try jsonData.write(to: fileURL, options: Data.WritingOptions.atomic)
            
            showingExportSuccess = true
        } catch {
            errorMessage = "Failed to export logs: \(error.localizedDescription)"
            showingError = true
        }
    }
    
    private func copyToClipboard() {
        do {
            let jsonData = try controller.diagnosticLogger.exportJSON()
            guard let jsonString = String(data: jsonData, encoding: .utf8) else {
                errorMessage = "Failed to convert logs to text"
                showingError = true
                return
            }
            
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(jsonString, forType: .string)
            
            showingClipboardSuccess = true
        } catch {
            errorMessage = "Failed to copy logs: \(error.localizedDescription)"
            showingError = true
        }
    }

    private func captureDeviceDetails() {
        isCapturingDeviceDetails = true

        Task {
            let captured = await controller.gatherDeviceDetails()
            isCapturingDeviceDetails = false

            if captured {
                showingDeviceDetailsSuccess = true
                updateCounts()
            } else {
                errorMessage = "Connect to a TV first, then try again."
                showingError = true
            }
        }
    }
}

// MARK: - Arylic Tab

#if LOCAL_ARYLIC_BUILD
struct ArylicTab: View {
    @Bindable var controller: TVController
    
    @State private var host: String = ""
    @State private var port: String = "80"
    @State private var timeout: String = "5.0"
    @State private var showingSaveConfirmation = false
    
    var body: some View {
        Form {
            Section {
                TextField("Host/IP Address", text: $host)
                    .textFieldStyle(.roundedBorder)
                    .help("e.g., 192.168.1.50 or arylic.local")
                
                TextField("Port", text: $port)
                    .textFieldStyle(.roundedBorder)
                    .help("Default: 80")
                
                TextField("Timeout (seconds)", text: $timeout)
                    .textFieldStyle(.roundedBorder)
                    .help("Default: 5.0")
            } header: {
                Text("Device Connection")
            }
            
            Section {
                HStack {
                    Text("Current Target:")
                    Spacer()
                    Text(controller.volumeControlTarget == .arylic ? "Arylic" : "TV")
                        .foregroundStyle(.secondary)
                }
                
                HStack {
                    Text("Settings Saved:")
                    Spacer()
                    Text(controller.arylicSettings != nil ? "Yes" : "No")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Status")
            }
            
            Section {
                Button("Test Connection") {
                    Task {
                        await controller.refreshArylicStatus()
                    }
                }
                .disabled(host.isEmpty)
                
                Button("Save Settings") {
                    saveSettings()
                }
                .buttonStyle(.borderedProminent)
                .disabled(host.isEmpty || port.isEmpty || timeout.isEmpty)
            } header: {
                Text("Actions")
            }
        }
        .formStyle(.columns)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .onAppear {
            loadSettings()
        }
        .alert("Settings Saved", isPresented: $showingSaveConfirmation) {
            Button("OK", role: .cancel) { }
        }
    }
    
    private func loadSettings() {
        if let settings = controller.arylicSettings {
            host = settings.host
            port = String(settings.port)
            timeout = String(settings.timeout)
        }
    }
    
    private func saveSettings() {
        guard let portInt = Int(port),
              let timeoutDouble = Double(timeout) else {
            return
        }
        
        let settings = ArylicSettings(
            host: host,
            port: portInt,
            timeout: timeoutDouble
        )
        
        controller.arylicSettings = settings
        showingSaveConfirmation = true
    }
}
#endif
