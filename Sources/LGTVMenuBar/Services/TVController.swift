import Foundation
import OSLog
import Observation

/// Central controller for TV operations
/// Orchestrates WebOSClient, WOLService, PowerManager, and other services
@MainActor
@Observable
public final class TVController: TVControllerProtocol {
    
    // MARK: - Published State (for UI binding)
    
    /// Current TV configuration (nil if not configured)
    public private(set) var configuration: TVConfiguration?
    
    /// Current connection state
    public private(set) var connectionState: ConnectionState = .disconnected {
        didSet {
            if oldValue != connectionState {
                logDiagnostic(level: "info", category: "TVController", message: "Connection state changed", metadata: ["oldState": "\(oldValue)", "newState": "\(connectionState)"])
                Task { await updateMediaKeyCapture() }
            }
        }
    }
    
    /// TV capabilities (populated after connection)
    public private(set) var capabilities: TVCapabilities?
    
    /// Current volume level (0-100)
    public private(set) var volume: Int = 0
    
    /// Whether TV is muted
    public private(set) var isMuted: Bool = false
    
    /// Current input
    public private(set) var currentInput: TVInputType?
    
    /// Current sound output
    public private(set) var soundOutput: TVSoundOutput = .unknown
    
    /// Whether media key capture is enabled
    public var isMediaKeyControlEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(isMediaKeyControlEnabled, forKey: mediaKeyEnabledKey)
            logger.info("Media key control \(self.isMediaKeyControlEnabled ? "enabled" : "disabled")")
            logDiagnostic(level: "info", category: "TVController", message: "Media key control \(self.isMediaKeyControlEnabled ? "enabled" : "disabled")")
            Task { await updateMediaKeyCapture() }
        }
    }
    
    // MARK: - Services
    
    private let webOSClient: WebOSClientProtocol
    private let wolService: WOLServiceProtocol
    private let powerManager: PowerManagerProtocol
    private let keychainManager: KeychainManagerProtocol
    private let mediaKeyManager: MediaKeyManagerProtocol
    private let launchAtLoginManager: LaunchAtLoginManagerProtocol
    /// Diagnostic logger for troubleshooting and log export
    public let diagnosticLogger: DiagnosticLoggerProtocol
    
    private let logger = Logger(subsystem: "com.lgtvmenubar", category: "TVController")
    private let mediaKeyEnabledKey = "isMediaKeyControlEnabled"
    private let configurationKey = "tv_configuration"
    private var diagnosticCaptureUntil: Date?
    private var diagnosticCaptureRestoreState: (enabled: Bool, debug: Bool)?
    private var diagnosticCaptureTimer: Timer?
    
    // MARK: - Debouncing
    /// Timestamp of last wake execution (for debouncing rapid wake events)
    private var lastWakeExecution: Date = .distantPast
    
    /// Timestamp of last sleep execution (for debouncing rapid sleep events)
    private var lastSleepExecution: Date = .distantPast
    
    /// Debounce interval in seconds (matches Hammerspoon's proven value)
    private let debounceInterval: TimeInterval = 10.0
    
    // MARK: - Initialization
    
    public init(
        webOSClient: WebOSClientProtocol,
        wolService: WOLServiceProtocol,
        powerManager: PowerManagerProtocol,
        keychainManager: KeychainManagerProtocol,
        mediaKeyManager: MediaKeyManagerProtocol,
        launchAtLoginManager: LaunchAtLoginManagerProtocol,
        diagnosticLogger: DiagnosticLoggerProtocol
    ) {
        self.webOSClient = webOSClient
        self.wolService = wolService
        self.powerManager = powerManager
        self.keychainManager = keychainManager
        self.mediaKeyManager = mediaKeyManager
        self.launchAtLoginManager = launchAtLoginManager
        self.diagnosticLogger = diagnosticLogger
        
        setupCallbacks()
        loadConfiguration()
    }
    
    /// Convenience initializer with default implementations
    public convenience init() {
        self.init(
            webOSClient: WebOSClient(),
            wolService: WOLService(),
            powerManager: PowerManager(),
            keychainManager: KeychainManager(),
            mediaKeyManager: MediaKeyManager(),
            launchAtLoginManager: LaunchAtLoginManager(),
            diagnosticLogger: DiagnosticLogger()
        )
        
        // Load persisted media key preference (without triggering didSet)
        let savedValue = UserDefaults.standard.bool(forKey: mediaKeyEnabledKey)
        if savedValue {
            // Set directly to avoid didSet during init
            self.isMediaKeyControlEnabled = savedValue
        }
    }
    
    // MARK: - Configuration
    
    /// Save TV configuration to UserDefaults
    public func saveConfiguration(_ config: TVConfiguration) throws {
        let data = try JSONEncoder().encode(config)
        UserDefaults.standard.set(data, forKey: configurationKey)
        self.configuration = config
        logger.info("Configuration saved for \(config.name)")
    }
    
    /// Clear TV configuration from UserDefaults
    public func clearConfiguration() throws {
        UserDefaults.standard.removeObject(forKey: configurationKey)
        self.configuration = nil
        logger.info("Configuration cleared")
    }
    
    // MARK: - Connection
    
    /// Connect to the configured TV
    public func connect() async throws {
        guard let config = configuration else {
            throw LGTVError.tvNotFound
        }
        
        logger.info("Connecting to \(config.name)")
        logDiagnostic(level: "info", category: "TVController", message: "Connecting to TV", metadata: ["connectionState": "\(connectionState)"])
        
        try await webOSClient.connect(to: config) { [weak self] state in
            Task { @MainActor in
                self?.connectionState = state
            }
        }

        await requestDeviceDetailsCommands()
    }
    
    /// Disconnect from the TV
    public func disconnect() {
        webOSClient.disconnect()
        connectionState = .disconnected
    }
    
    /// Attempt to connect on app startup with retry logic
    public func autoConnectOnStartup() async {
        guard let config = configuration, config.autoConnectOnLaunch else { return }
        
        logger.info("Auto-connecting to TV on startup")
        
        // Retry up to 3 times with increasing delays
        for attempt in 1...3 {
            do {
                try await connect()
                logger.info("Auto-connect successful on attempt \(attempt)")
                logDiagnostic(level: "info", category: "TVController", message: "Auto-connect successful", metadata: ["attempt": "\(attempt)"])
                return
            } catch {
                logger.warning("Auto-connect attempt \(attempt) failed: \(error.localizedDescription)")
                logDiagnostic(level: "warning", category: "TVController", message: "Auto-connect attempt failed", metadata: ["attempt": "\(attempt)", "error": error.localizedDescription])
                if attempt < 3 {
                    try? await Task.sleep(for: .seconds(Double(attempt) * 2))
                }
            }
        }
        logger.error("Auto-connect failed after 3 attempts")
        logDiagnostic(level: "error", category: "TVController", message: "Auto-connect failed after 3 attempts")
    }
    
    /// Wake TV via Wake-on-LAN
    public func wake() async throws {
        guard let config = configuration else {
            throw LGTVError.tvNotFound
        }
        
        logger.info("Sending WOL to \(config.name)")
        try await wolService.sendWakeOnLAN(macAddress: config.macAddress)
    }
    
    // MARK: - Power Control
    
    /// Turn off the TV
    public func powerOff() async throws {
        try await webOSClient.sendCommand(.powerOff)
    }
    
    /// Turn off the TV screen (display only, TV stays on)
    public func screenOff() async throws {
        try await webOSClient.sendCommand(.screenOff)
    }
    
    /// Turn on the TV screen
    public func screenOn() async throws {
        try await webOSClient.sendCommand(.screenOn)
    }
    
    // MARK: - Volume Control
    
    /// Increase volume
    public func volumeUp() async throws {
        try await webOSClient.sendCommand(.volumeUp)
    }
    
    /// Decrease volume
    public func volumeDown() async throws {
        try await webOSClient.sendCommand(.volumeDown)
    }
    
    /// Set specific volume level
    public func setVolume(_ level: Int) async throws {
        let clampedLevel = max(0, min(100, level))
        try await webOSClient.sendCommand(.setVolume(clampedLevel))
        self.volume = clampedLevel
    }
    
    /// Toggle mute
    public func toggleMute() async throws {
        if isMuted {
            try await webOSClient.sendCommand(.unmute)
        } else {
            try await webOSClient.sendCommand(.mute)
        }
        isMuted.toggle()
    }
    
    // MARK: - Input Control
    
    /// Switch to specified input
    public func switchInput(_ input: TVInputType) async throws {
        try await webOSClient.sendCommand(.setInput(input.rawValue))
        currentInput = input
    }
    
    /// Set TV sound output
    /// - Parameter output: The sound output to switch to
    public func setSoundOutput(_ output: TVSoundOutput) async throws {
        try await webOSClient.sendCommand(.setSoundOutput(output.rawValue))
        soundOutput = output
    }

    // MARK: - Diagnostics

    public func setDiagnosticLoggingEnabled(_ enabled: Bool) {
        if enabled {
            diagnosticLogger.enable()
        } else {
            diagnosticLogger.disable()
        }

        updateDiagnosticCaptureSchedule()
    }

    public func setDiagnosticDebugMode(_ enabled: Bool) {
        diagnosticLogger.setDebugMode(enabled)
        updateDiagnosticCaptureSchedule()
    }

    public func gatherDeviceDetails() async -> Bool {
        guard connectionState.isConnected else {
            logDiagnostic(level: "warning", category: "TVController", message: "Device details capture skipped - not connected", metadata: deviceDetailsMetadata())
            return false
        }

        let wasEnabled = diagnosticLogger.isEnabled
        let wasDebugMode = diagnosticLogger.isDebugMode

        if !wasEnabled {
            diagnosticLogger.enable()
        }

        if !wasDebugMode {
            diagnosticLogger.setDebugMode(true)
        }

        if !wasEnabled || !wasDebugMode {
            diagnosticCaptureRestoreState = (enabled: wasEnabled, debug: wasDebugMode)
        }

        diagnosticCaptureUntil = Date().addingTimeInterval(8)
        updateDiagnosticCaptureSchedule()

        logDiagnostic(level: "warning", category: "TVController", message: "Device details capture requested", metadata: deviceDetailsMetadata())

        await requestDeviceDetailsCommands()

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(8))
            self?.diagnosticCaptureUntil = nil
            self?.restoreDiagnosticStateIfNeeded()
        }

        return true
    }
    
    /// Set PC mode for a specific input
    /// - Parameters:
    ///   - input: The input to set PC mode on
    ///   - enabled: Whether to enable or disable PC mode
    public func setPCMode(for input: TVInputType, enabled: Bool) async throws {
        let icon = enabled ? "pc" : "hdmi"
        let label = enabled ? "PC" : input.displayName
        try await webOSClient.sendCommand(.setDeviceInfo(inputId: input.rawValue, icon: icon, label: label))
        logger.info("Set PC mode \(enabled ? "enabled" : "disabled") for \(input.rawValue)")
    }
    
    // MARK: - Launch at Login
    
    /// Check if launch at login is enabled
    public func isLaunchAtLoginEnabled() async throws -> Bool {
        try await launchAtLoginManager.isLaunchAtLoginEnabled()
    }
    
    /// Set launch at login state
    public func setLaunchAtLogin(_ enabled: Bool) async throws {
        if enabled {
            try await launchAtLoginManager.enableLaunchAtLogin()
        } else {
            try await launchAtLoginManager.disableLaunchAtLogin()
        }
    }

    // MARK: - Accessibility

    public func hasAccessibilityPermission() -> Bool {
        mediaKeyManager.hasAccessibilityPermission
    }

    public func requestAccessibilityPermission() -> Bool {
        mediaKeyManager.requestAccessibilityPermission()
    }

    public func refreshMediaKeyCapture() {
        Task { await updateMediaKeyCapture() }
    }
    
    // MARK: - Private Methods
    
    private func setupCallbacks() {
        // WebOS capability updates
        webOSClient.setCapabilityCallback { [weak self] capabilities in
            guard let self = self else { return }
            Task { @MainActor [weak self] in
                self?.capabilities = capabilities
            }
        }
        
        // WebOS input changes
        webOSClient.setInputChangeCallback { [weak self] input in
            guard let self = self else { return }
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.currentInput = input
                if self.isDiagnosticCaptureActive {
                    self.logDiagnostic(level: "warning", category: "TVController", message: "Current input updated", metadata: ["currentInput": input.displayName])
                }
            }
        }
        
        // WebOS volume changes
        webOSClient.setVolumeChangeCallback { [weak self] volume, isMuted in
            guard let self = self else { return }
            Task { @MainActor [weak self] in
                self?.volume = volume
                self?.isMuted = isMuted
            }
        }
        
        // WebOS input list updates (for PC mode detection)
        webOSClient.setInputListCallback { [weak self] inputIcons in
            guard let self = self else { return }
            Task { @MainActor [weak self] in
                self?.capabilities?.inputIcons = inputIcons
                // Log PC mode status for preferred input
                if let config = self?.configuration,
                   let preferredInputIcon = inputIcons[config.preferredInput] {
                    if preferredInputIcon.contains("pc") {
                        self?.logger.info("TV input \(config.preferredInput) is in PC mode")
                    }
                }
            }
        }
        
        // WebOS sound output changes
        webOSClient.setSoundOutputChangeCallback { [weak self] output in
            Task { @MainActor [weak self] in
                guard let self = self else { return }

                if output == .unknown && self.soundOutput != .unknown {
                    if self.isDiagnosticCaptureActive {
                        self.logDiagnostic(level: "warning", category: "TVController", message: "Ignored unknown sound output", metadata: ["currentSoundOutput": self.soundOutput.displayName])
                    }
                    return
                }

                self.soundOutput = output
                if self.isDiagnosticCaptureActive {
                    self.logDiagnostic(level: "warning", category: "TVController", message: "Sound output updated", metadata: ["soundOutput": output.displayName])
                }
            }
        }

        webOSClient.setDiagnosticPayloadCallback { [weak self] messageType, payloadJSON in
            guard let self = self else { return }
            if self.isDiagnosticCaptureActive {
                self.logDiagnostic(level: "warning", category: "WebOSClient", message: "Captured \(messageType) payload", metadata: ["payload": payloadJSON])
            }
        }
        
        // Power manager sleep/wake events
        var powerManagerMutable = powerManager
        powerManagerMutable.onWake = { [weak self] in
            guard let self = self else { return }
            Task { @MainActor [weak self] in
                await self?.handleMacWake()
            }
        }
        
        powerManagerMutable.onSleep = { [weak self] in
            guard let self = self else { return }
            Task { @MainActor [weak self] in
                await self?.handleMacSleep()
            }
        }
        
        // Screen wake events (display wakes without full system sleep)
        powerManagerMutable.onScreenWake = { [weak self] in
            guard let self = self else { return }
            Task { @MainActor [weak self] in
                await self?.handleMacWake()
            }
        }
        
        // Start monitoring
        powerManager.startMonitoring()
    }
    
    private func loadConfiguration() {
        guard let data = UserDefaults.standard.data(forKey: configurationKey) else {
            configuration = nil
            return
        }
        
        do {
            configuration = try JSONDecoder().decode(TVConfiguration.self, from: data)
            if let config = configuration {
                logger.info("Loaded configuration for \(config.name)")
            }
        } catch {
            logger.error("Failed to decode configuration: \(error.localizedDescription)")
            configuration = nil
        }
    }
    
    private func handleMacWake() async {
        guard let config = configuration, config.wakeWithMac else { return }
        
        // Debounce: prevent duplicate wake attempts within 10 seconds
        let now = Date()
        let timeSinceLastWake = now.timeIntervalSince(lastWakeExecution)
        if timeSinceLastWake < debounceInterval {
            logger.info("Skipping wake - debounced (last execution \(String(format: "%.1f", timeSinceLastWake))s ago)")
            logDiagnostic(level: "info", category: "TVController", message: "Wake attempt debounced", metadata: ["timeSinceLastWake": "\(String(format: "%.1f", timeSinceLastWake))s"])
            return
        }
        lastWakeExecution = now
        
        logger.info("Mac woke - waking TV")
        logDiagnostic(level: "info", category: "TVController", message: "Mac woke - waking TV")
        
        // Always disconnect first to ensure clean state for reconnection
        disconnect()
        
        do {
            try await wake()
            // Wait a bit for TV to boot, then connect
            try await Task.sleep(for: .seconds(3))
            try await connect()
            
            // Explicitly turn screen on
            logger.info("Turning TV screen on")
            logDiagnostic(level: "info", category: "TVController", message: "Turning TV screen on")
            try await screenOn()
            
            if config.switchInputOnWake {
                if let input = TVInputType(rawValue: config.preferredInput) {
                    try await switchInput(input)
                }
            }
            
            // Set PC mode if enabled and not already set
            if config.enablePCMode {
                let currentIcon = capabilities?.inputIcons[config.preferredInput] ?? ""
                if !currentIcon.contains("pc") {
                    logger.info("Setting PC mode for \(config.preferredInput)")
                    if let input = TVInputType(rawValue: config.preferredInput) {
                        try await setPCMode(for: input, enabled: true)
                    }
                }
            }
        } catch {
            logger.error("Failed to wake TV: \(error.localizedDescription)")
            logDiagnostic(level: "error", category: "TVController", message: "Failed to wake TV", metadata: ["error": error.localizedDescription])
        }
    }
    
    private func handleMacSleep() async {
        guard let config = configuration, config.sleepWithMac else { return }
        
        // Debounce: prevent duplicate sleep attempts within 10 seconds
        let now = Date()
        let timeSinceLastSleep = now.timeIntervalSince(lastSleepExecution)
        if timeSinceLastSleep < debounceInterval {
            logger.info("Skipping sleep - debounced (last execution \(String(format: "%.1f", timeSinceLastSleep))s ago)")
            logDiagnostic(level: "info", category: "TVController", message: "Sleep attempt debounced", metadata: ["timeSinceLastSleep": "\(String(format: "%.1f", timeSinceLastSleep))s"])
            return
        }
        lastSleepExecution = now
        
        // Don't sleep TV if user is on a different input (e.g., watching console, streaming device)
        if let currentInput = currentInput {
            if currentInput.rawValue != config.preferredInput {
                logger.info("Skipping TV sleep - TV is on different input: \(currentInput.displayName) (preferred: \(config.preferredInput))")
                logDiagnostic(level: "info", category: "TVController", message: "Skipping TV sleep - different input", metadata: ["currentInput": currentInput.displayName, "preferredInput": config.preferredInput])
                disconnect()
                return
            }
        }
        // If currentInput is nil (unknown), we proceed with sleep as a safe default
        // since we can't determine what the user is doing
        
        logger.info("Mac sleeping - turning off TV")
        logDiagnostic(level: "info", category: "TVController", message: "Mac sleeping - turning off TV")
        do {
            try await powerOff()
        } catch {
            logger.error("Failed to turn off TV: \(error.localizedDescription)")
            logDiagnostic(level: "error", category: "TVController", message: "Failed to turn off TV", metadata: ["error": error.localizedDescription])
        }
        disconnect()
    }
    
    private func updateMediaKeyCapture() async {
        if isMediaKeyControlEnabled && connectionState.isConnected {
            if !mediaKeyManager.hasAccessibilityPermission {
                logger.warning("Disabling media key control - Accessibility permission not granted")
                logDiagnostic(level: "warning", category: "TVController", message: "Disabling media key control - Accessibility permission not granted", metadata: appIdentityMetadata())
                isMediaKeyControlEnabled = false
                return
            }
            do {
                try await mediaKeyManager.startMediaKeyCapture { [weak self] key in
                    Task { @MainActor in
                        await self?.handleMediaKey(key)
                    }
                }
            } catch {
                logger.error("Failed to start media key capture: \(error.localizedDescription)")
                var metadata = appIdentityMetadata()
                metadata["error"] = error.localizedDescription
                metadata["accessibilityTrusted"] = "\(mediaKeyManager.hasAccessibilityPermission)"
                logDiagnostic(level: "error", category: "TVController", message: "Failed to start media key capture", metadata: metadata)
            }
        } else {
            do {
                try await mediaKeyManager.stopMediaKeyCapture()
            } catch {
                logger.error("Failed to stop media key capture: \(error.localizedDescription)")
                logDiagnostic(level: "error", category: "TVController", message: "Failed to stop media key capture", metadata: ["error": error.localizedDescription])
            }
        }
    }
    
    private func handleMediaKey(_ key: MediaKey) async {
        guard connectionState.isConnected else { return }
        
        do {
            switch key {
            case .volumeUp:
                try await volumeUp()
            case .volumeDown:
                try await volumeDown()
            case .mute:
                try await toggleMute()
            }
        } catch {
            logger.error("Failed to handle media key: \(error.localizedDescription)")
            logDiagnostic(level: "error", category: "TVController", message: "Failed to handle media key", metadata: ["error": error.localizedDescription])
        }
    }
    
    // MARK: - Diagnostic Logging
    
    private func logDiagnostic(level: String, category: String, message: String, metadata: [String: String]? = nil) {
        diagnosticLogger.log(level: level, category: category, message: message, metadata: metadata)
    }

    private func appIdentityMetadata() -> [String: String] {
        var metadata: [String: String] = [:]
        metadata["bundleIdentifier"] = Bundle.main.bundleIdentifier ?? "unknown"
        metadata["bundlePath"] = Bundle.main.bundleURL.path
        metadata["executablePath"] = Bundle.main.executableURL?.path ?? "unknown"
        return metadata
    }

    private func deviceDetailsMetadata() -> [String: String] {
        var metadata: [String: String] = [
            "connectionState": "\(connectionState)",
            "currentInput": currentInput?.displayName ?? "unknown",
            "soundOutput": soundOutput.displayName,
            "volume": "\(volume)",
            "isMuted": "\(isMuted)"
        ]

        if let config = configuration {
            metadata["tvName"] = config.name
            metadata["ipAddress"] = config.ipAddress
            metadata["preferredInput"] = config.preferredInput
        }

        return metadata
    }

    private var isDiagnosticCaptureActive: Bool {
        if let captureUntil = diagnosticCaptureUntil {
            return Date() <= captureUntil
        }
        return false
    }

    private func restoreDiagnosticStateIfNeeded() {
        guard let restoreState = diagnosticCaptureRestoreState else { return }

        diagnosticLogger.setDebugMode(restoreState.debug)
        if !restoreState.enabled {
            diagnosticLogger.disable()
        }

        diagnosticCaptureRestoreState = nil
        updateDiagnosticCaptureSchedule()
    }

    private func updateDiagnosticCaptureSchedule() {
        if diagnosticLogger.isEnabled && diagnosticLogger.isDebugMode {
            startDiagnosticCaptureTimer()
        } else {
            stopDiagnosticCaptureTimer()
        }
    }

    private func startDiagnosticCaptureTimer() {
        stopDiagnosticCaptureTimer()

        diagnosticCaptureTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.capturePeriodicDiagnostics()
            }
        }
    }

    private func stopDiagnosticCaptureTimer() {
        diagnosticCaptureTimer?.invalidate()
        diagnosticCaptureTimer = nil
    }

    private func capturePeriodicDiagnostics() {
        guard connectionState.isConnected else {
            logDiagnostic(level: "info", category: "TVController", message: "Skipped periodic capture - not connected", metadata: deviceDetailsMetadata())
            return
        }

        logDiagnostic(level: "info", category: "TVController", message: "Periodic device status snapshot", metadata: deviceDetailsMetadata())

        Task { @MainActor in
            await requestDeviceDetailsCommands()
        }
    }

    private func requestDeviceDetailsCommands() async {
        do {
            try await webOSClient.sendCommand(.getCurrentForegroundAppInfo)
        } catch {
            logDiagnostic(level: "warning", category: "TVController", message: "Failed to request foreground app info", metadata: ["error": error.localizedDescription])
        }

        do {
            try await webOSClient.sendCommand(.getInputList)
        } catch {
            logDiagnostic(level: "warning", category: "TVController", message: "Failed to request input list", metadata: ["error": error.localizedDescription])
        }

        do {
            try await webOSClient.sendCommand(.getSoundOutput)
        } catch {
            logDiagnostic(level: "warning", category: "TVController", message: "Failed to request sound output", metadata: ["error": error.localizedDescription])
        }

        do {
            try await webOSClient.sendCommand(.getVolume)
        } catch {
            logDiagnostic(level: "warning", category: "TVController", message: "Failed to request volume", metadata: ["error": error.localizedDescription])
        }
    }
}
