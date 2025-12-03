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
    
    /// Whether media key capture is enabled
    public var isMediaKeyControlEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(isMediaKeyControlEnabled, forKey: mediaKeyEnabledKey)
            logger.info("Media key control \(self.isMediaKeyControlEnabled ? "enabled" : "disabled")")
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
    
    private let logger = Logger(subsystem: "com.lgtvmenubar", category: "TVController")
    private let mediaKeyEnabledKey = "isMediaKeyControlEnabled"
    
    // MARK: - Initialization
    
    public init(
        webOSClient: WebOSClientProtocol,
        wolService: WOLServiceProtocol,
        powerManager: PowerManagerProtocol,
        keychainManager: KeychainManagerProtocol,
        mediaKeyManager: MediaKeyManagerProtocol,
        launchAtLoginManager: LaunchAtLoginManagerProtocol
    ) {
        self.webOSClient = webOSClient
        self.wolService = wolService
        self.powerManager = powerManager
        self.keychainManager = keychainManager
        self.mediaKeyManager = mediaKeyManager
        self.launchAtLoginManager = launchAtLoginManager
        
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
            launchAtLoginManager: LaunchAtLoginManager()
        )
        
        // Load persisted media key preference (without triggering didSet)
        let savedValue = UserDefaults.standard.bool(forKey: mediaKeyEnabledKey)
        if savedValue {
            // Set directly to avoid didSet during init
            self.isMediaKeyControlEnabled = savedValue
        }
    }
    
    // MARK: - Configuration
    
    /// Save TV configuration
    public func saveConfiguration(_ config: TVConfiguration) throws {
        try keychainManager.saveConfiguration(config)
        self.configuration = config
        logger.info("Configuration saved for \(config.name)")
    }
    
    /// Clear TV configuration
    public func clearConfiguration() throws {
        try keychainManager.deleteConfiguration()
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
        
        try await webOSClient.connect(to: config) { [weak self] state in
            Task { @MainActor in
                self?.connectionState = state
            }
        }
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
                return
            } catch {
                logger.warning("Auto-connect attempt \(attempt) failed: \(error.localizedDescription)")
                if attempt < 3 {
                    try? await Task.sleep(for: .seconds(Double(attempt) * 2))
                }
            }
        }
        logger.error("Auto-connect failed after 3 attempts")
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
                self?.currentInput = input
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
        
        // Start monitoring
        powerManager.startMonitoring()
    }
    
    private func loadConfiguration() {
        do {
            configuration = try keychainManager.loadConfiguration()
            if let config = configuration {
                logger.info("Loaded configuration for \(config.name)")
            }
        } catch {
            logger.error("Failed to load configuration: \(error.localizedDescription)")
        }
    }
    
    private func handleMacWake() async {
        guard let config = configuration, config.wakeWithMac else { return }
        
        logger.info("Mac woke - waking TV")
        do {
            try await wake()
            // Wait a bit for TV to boot, then connect
            try await Task.sleep(for: .seconds(3))
            try await connect()
            
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
        }
    }
    
    private func handleMacSleep() async {
        guard let config = configuration, config.sleepWithMac else { return }
        
        // Don't sleep TV if user is on a different input (e.g., watching console, streaming device)
        if let currentInput = currentInput {
            if currentInput.rawValue != config.preferredInput {
                logger.info("Skipping TV sleep - TV is on different input: \(currentInput.displayName) (preferred: \(config.preferredInput))")
                disconnect()
                return
            }
        }
        // If currentInput is nil (unknown), we proceed with sleep as a safe default
        // since we can't determine what the user is doing
        
        logger.info("Mac sleeping - turning off TV")
        do {
            try await powerOff()
        } catch {
            logger.error("Failed to turn off TV: \(error.localizedDescription)")
        }
        disconnect()
    }
    
    private func updateMediaKeyCapture() async {
        if isMediaKeyControlEnabled && connectionState.isConnected {
            do {
                try await mediaKeyManager.startMediaKeyCapture { [weak self] key in
                    Task { @MainActor in
                        await self?.handleMediaKey(key)
                    }
                }
            } catch {
                logger.error("Failed to start media key capture: \(error.localizedDescription)")
            }
        } else {
            do {
                try await mediaKeyManager.stopMediaKeyCapture()
            } catch {
                logger.error("Failed to stop media key capture: \(error.localizedDescription)")
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
        }
    }
}
