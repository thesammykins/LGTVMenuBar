import CoreGraphics
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
                connectionStateDidChange?(connectionState)
                Task { await updateMediaKeyCapture() }
                handleConnectionStateChange()
            }
        }
    }

    @ObservationIgnored
    var connectionStateDidChange: ((ConnectionState) -> Void)?

    /// Observer for foreground changes (used by Display Lock).
    @ObservationIgnored
    var foregroundDidChange: ((TVForeground) -> Void)?

    /// Observer for configuration changes (used by Display Lock).
    @ObservationIgnored
    var configurationDidChange: ((TVConfiguration?) -> Void)?
    
    /// TV capabilities (populated after connection)
    public private(set) var capabilities: TVCapabilities?
    
    /// Current volume level (0-100)
    public private(set) var volume: Int = 0
    
    /// Whether TV is muted
    public private(set) var isMuted: Bool = false
    
    /// The TV input in front, or nil when the TV is showing an app or nothing is known.
    public private(set) var currentInput: TVInputType?

    /// What the TV is showing: one of its inputs, an app, or unknown.
    public private(set) var foreground: TVForeground = .unknown

    /// True after the TV refused or ignored pairing. Automatic connects stop until the user
    /// connects by hand, so the TV is never prompted in a loop.
    public private(set) var pairingRequiresUser = false

    /// Kinds of automation currently suspended by the action governor.
    public private(set) var suspendedAutomation: [ActionGovernor.Kind] = []

    /// Media keys are wanted but macOS Accessibility permission is missing.
    public private(set) var isMediaKeyPermissionMissing = false

    /// The OLED panel's maintenance state; nil without root access or on a TV that lacks it.
    public private(set) var panelCare: PanelCareStatus?
    /// When the app last saw a pixel refresh, for "use since the last refresh".
    public private(set) var panelCareHistory: PanelCareHistory?

    /// When the app switched the TV off for a pixel refresh that is still being left alone.
    public private(set) var pixelRefreshStartedAt: Date?
    
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
    
    #if LOCAL_ARYLIC_BUILD
    /// Whether Arylic volume control is enabled (persisted to UserDefaults)
    public var isArylicVolumeControlEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(isArylicVolumeControlEnabled, forKey: arylicVolumeControlEnabledKey)
            logger.info("Arylic volume control \(self.isArylicVolumeControlEnabled ? "enabled" : "disabled")")
            logDiagnostic(level: "info", category: "TVController", message: "Arylic volume control \(self.isArylicVolumeControlEnabled ? "enabled" : "disabled")")
        }
    }
    
    /// Volume control target (TV or Arylic) (persisted to UserDefaults)
    public var volumeControlTarget: VolumeControlTarget = .tv {
        didSet {
            UserDefaults.standard.set(volumeControlTarget.rawValue, forKey: volumeControlTargetKey)
            logger.info("Volume control target changed to \(self.volumeControlTarget.rawValue)")
            logDiagnostic(level: "info", category: "TVController", message: "Volume control target changed", metadata: ["target": volumeControlTarget.rawValue])
            
            // Refresh Arylic status when switching to Arylic target
            if volumeControlTarget == .arylic && isArylicVolumeControlEnabled {
                Task {
                    await refreshArylicStatus()
                }
            }
        }
    }
    
    /// Arylic device settings (persisted to UserDefaults)
    public var arylicSettings: ArylicSettings? {
        didSet {
            if let settings = arylicSettings {
                if let data = try? JSONEncoder().encode(settings) {
                    UserDefaults.standard.set(data, forKey: arylicSettingsKey)
                }
                // Recreate client with new settings
                arylicClient = ArylicVolumeClient(settings: settings)
                logger.info("Arylic settings updated: \(settings.host):\(settings.port)")
                logDiagnostic(level: "info", category: "TVController", message: "Arylic settings updated", metadata: ["host": settings.host, "port": "\(settings.port)"])
            } else {
                UserDefaults.standard.removeObject(forKey: arylicSettingsKey)
                arylicClient = nil
                logger.info("Arylic settings cleared")
                logDiagnostic(level: "info", category: "TVController", message: "Arylic settings cleared")
            }
        }
    }
    
    /// Arylic client (lazily created when settings are configured)
    private var arylicClient: ArylicVolumeClientProtocol?
    #endif
    
    // MARK: - Services
    
    private let webOSClient: WebOSClientProtocol
    private let wolService: WOLServiceProtocol
    private let powerManager: PowerManagerProtocol
    private let keychainManager: KeychainManagerProtocol
    private let mediaKeyManager: MediaKeyManagerProtocol
    private let launchAtLoginManager: LaunchAtLoginManagerProtocol
    /// Nil disables probing and background reconnects (unit tests with mocked transports).
    private let reachabilityProbe: TVReachabilityProbing?
    /// Seconds since the last keyboard or mouse input. Nil reads as "someone is here".
    private let userIdleSeconds: (@MainActor () -> TimeInterval)?
    private let panelCareGraceDelay: Duration
    private let panelCarePollInterval: Duration
    private let panelCareHistoryStore: PanelCareHistoryStoring?
    private let now: @MainActor () -> Date
    /// Asks macOS whether the session is locked. Nil falls back to the lock notifications,
    /// which macOS does not post when the lock comes from the display going to sleep.
    private let isScreenLocked: (@MainActor () -> Bool)?
    /// Diagnostic logger for troubleshooting and log export
    public let diagnosticLogger: DiagnosticLoggerProtocol

    /// Optional shell access to a rooted TV.
    public let rootAccess: RootAccessService

    @ObservationIgnored
    private lazy var privilegedCalls = TVPrivilegedCalls(client: webOSClient, root: rootAccess) { [weak self] level, message, metadata in
        self?.logDiagnostic(level: level, category: "PrivilegedCalls", message: message, metadata: metadata)
    }
    
    private let logger = Logger(subsystem: "com.lgtvmenubar", category: "TVController")
    private let mediaKeyEnabledKey = "isMediaKeyControlEnabled"
    #if LOCAL_ARYLIC_BUILD
    private let arylicVolumeControlEnabledKey = "arylicVolumeControlEnabled"
    private let volumeControlTargetKey = "volumeControlTarget"
    private let arylicSettingsKey = "arylicSettings"
    #endif
    private let configurationKey = "tv_configuration"
    private var diagnosticCaptureUntil: Date?
    private var diagnosticCaptureRestoreState: (enabled: Bool, debug: Bool)?
    private var diagnosticCaptureTimer: Timer?
    private var lastPeriodicSnapshotMetadata: [String: String]?
    
    // MARK: - Debouncing
    /// Prevent overlapping wake sequences while a previous wake is still running.
    private var isWakeInProgress = false

    /// Prevent duplicate wake notifications from queueing multiple recovery tasks.
    private var isWakeRecoveryQueued = false

    /// Most recent wake-recovery task started from a power notification.
    @ObservationIgnored
    internal private(set) var wakeRecoveryTask: Task<Void, Never>?

    /// Shared connection task used to avoid restarting a pairing handshake.
    @ObservationIgnored
    private var connectTask: Task<Void, Error>?

    /// Identifies the task in `connectTask`, so a finished attempt cannot clear a newer one.
    @ObservationIgnored
    private var connectTaskID: UInt64 = 0

    /// Background loop that reconnects once the TV is reachable again.
    @ObservationIgnored
    private var reconnectTask: Task<Void, Never>?

    /// Set between the Mac's sleep and wake notifications. Nothing reconnects while asleep.
    @ObservationIgnored
    private var isMacAsleep = false

    /// Loop guard for every automatic action that changes the TV.
    @ObservationIgnored
    private var governor = ActionGovernor()

    /// The user chose Disconnect; background reconnects stay off until they connect again.
    @ObservationIgnored
    private var userDisconnected = false

    /// Position in `ReconnectSchedule`. Kept across reconnect loops so a TV that accepts a
    /// connection and drops it straight away is retried with backoff, not every two seconds.
    @ObservationIgnored
    private var reconnectAttempt = 0

    @ObservationIgnored
    private var lastConnectedAt: ContinuousClock.Instant?

    /// Waits out a brief lock or display sleep before switching the TV off for a refresh.
    @ObservationIgnored
    private var downtimeTask: Task<Void, Never>?

    @ObservationIgnored
    private var panelCareRetryTask: Task<Void, Never>?

    /// The TV's refresh counter when a quiet period began, to tell afterwards whether one ran.
    @ObservationIgnored
    private var refreshCountBeforeQuietPeriod: Int?
    /// Set when this app switched the TV off for a refresh at a lock, until a wake undoes it.
    private var tvIsOffForPixelRefresh = false
    private var presenceWatchTask: Task<Void, Never>?
    /// The last power state the TV reported on this session was standby.
    private var tvReportedStandby = false
    /// How many times a wake is sent to a TV that is still off after the first.
    private static let wakeRounds = 2

    /// Watches a refresh in progress and ends the quiet period when it finishes.
    @ObservationIgnored
    private var refreshMonitorTask: Task<Void, Never>?

    /// Between the lock and unlock notifications. A refresh is only made room for while this
    /// is true (or the Mac is asleep); it never takes the display from someone using the Mac.
    @ObservationIgnored
    private var isMacLocked = false

    /// A wake that arrived with nobody at the Mac while a refresh was running.
    @ObservationIgnored
    private var heldWakeReason: String?

    /// One-off delay for the next reconnect check, used after finding the TV in standby.
    @ObservationIgnored
    private var reconnectDelayOverride: Duration?

    private static let standbyRecheckDelay: Duration = .seconds(300)
    
    /// Timestamp of last sleep execution (for debouncing rapid sleep events)
    private var lastSleepExecution: Date = .distantPast
    
    /// Debounce interval in seconds for repeated sleep events.
    private let sleepDebounceInterval: TimeInterval

    /// Delay before the first reconnect attempt after sending Wake-on-LAN.
    private let wakeConnectInitialDelay: Duration

    /// Delay between reconnect attempts after a failed wake reconnect.
    private let wakeConnectRetryDelay: Duration

    /// Maximum number of reconnect attempts after wake.
    private let wakeConnectMaxAttempts: Int

    /// How long a wake waits for the TV's control port before trying to connect regardless.
    private let wakePortWait: Duration

    /// Maximum time spent polling WebOS after Wake-on-LAN before giving up.
    private let wakeConnectTimeout: Duration

    private enum ScreenRecoveryOutcome: Equatable {
        case alreadyAwake
        case screenOnSent
        case needsPowerOn
        /// Active Standby: the TV is off as far as the viewer is concerned, but still answering.
        case standby
        case connectionLost
        /// The TV is part-way through switching off.
        case turningOff
        case skipped
    }
    
    // MARK: - Initialization
    
    public init(
        webOSClient: WebOSClientProtocol,
        wolService: WOLServiceProtocol,
        powerManager: PowerManagerProtocol,
        keychainManager: KeychainManagerProtocol,
        mediaKeyManager: MediaKeyManagerProtocol,
        launchAtLoginManager: LaunchAtLoginManagerProtocol,
        diagnosticLogger: DiagnosticLoggerProtocol,
        reachabilityProbe: TVReachabilityProbing? = nil,
        rootAccess: RootAccessService? = nil,
        userIdleSeconds: (@MainActor () -> TimeInterval)? = nil,
        panelCareGraceDelay: Duration = .seconds(60),
        panelCarePollInterval: Duration = .seconds(30),
        panelCareHistoryStore: PanelCareHistoryStoring? = nil,
        now: @escaping @MainActor () -> Date = { Date() },
        isScreenLocked: (@MainActor () -> Bool)? = nil,
        sleepDebounceInterval: TimeInterval = 10.0,
        wakeConnectInitialDelay: Duration = .seconds(1),
        wakeConnectRetryDelay: Duration = .seconds(2),
        wakeConnectMaxAttempts: Int = 45,
        wakeConnectTimeout: Duration = .seconds(90),
        wakePortWait: Duration = .seconds(12)
    ) {
        self.webOSClient = webOSClient
        self.wolService = wolService
        self.powerManager = powerManager
        self.keychainManager = keychainManager
        self.mediaKeyManager = mediaKeyManager
        self.launchAtLoginManager = launchAtLoginManager
        self.diagnosticLogger = diagnosticLogger
        self.reachabilityProbe = reachabilityProbe
        self.rootAccess = rootAccess ?? RootAccessService(keychain: keychainManager)
        self.userIdleSeconds = userIdleSeconds
        self.panelCareGraceDelay = panelCareGraceDelay
        self.panelCarePollInterval = panelCarePollInterval
        self.panelCareHistoryStore = panelCareHistoryStore
        self.panelCareHistory = panelCareHistoryStore?.load()
        self.now = now
        self.isScreenLocked = isScreenLocked
        self.sleepDebounceInterval = max(0, sleepDebounceInterval)
        self.wakeConnectInitialDelay = wakeConnectInitialDelay
        self.wakeConnectRetryDelay = wakeConnectRetryDelay
        self.wakeConnectMaxAttempts = max(1, wakeConnectMaxAttempts)
        self.wakeConnectTimeout = wakeConnectTimeout
        self.wakePortWait = wakePortWait
        
        setupCallbacks()
        loadConfiguration()
        #if LOCAL_ARYLIC_BUILD
        loadArylicConfiguration()
        #endif
    }
    
    #if LOCAL_ARYLIC_BUILD
    /// Internal initializer for testing with injectable Arylic client
    internal init(
        webOSClient: WebOSClientProtocol,
        wolService: WOLServiceProtocol,
        powerManager: PowerManagerProtocol,
        keychainManager: KeychainManagerProtocol,
        mediaKeyManager: MediaKeyManagerProtocol,
        launchAtLoginManager: LaunchAtLoginManagerProtocol,
        diagnosticLogger: DiagnosticLoggerProtocol,
        arylicClient: ArylicVolumeClientProtocol?,
        reachabilityProbe: TVReachabilityProbing? = nil,
        rootAccess: RootAccessService? = nil,
        userIdleSeconds: (@MainActor () -> TimeInterval)? = nil,
        panelCareGraceDelay: Duration = .seconds(60),
        panelCarePollInterval: Duration = .seconds(30),
        panelCareHistoryStore: PanelCareHistoryStoring? = nil,
        now: @escaping @MainActor () -> Date = { Date() },
        isScreenLocked: (@MainActor () -> Bool)? = nil,
        sleepDebounceInterval: TimeInterval = 10.0,
        wakeConnectInitialDelay: Duration = .seconds(1),
        wakeConnectRetryDelay: Duration = .seconds(2),
        wakeConnectMaxAttempts: Int = 45,
        wakeConnectTimeout: Duration = .seconds(90),
        wakePortWait: Duration = .seconds(12)
    ) {
        self.webOSClient = webOSClient
        self.wolService = wolService
        self.powerManager = powerManager
        self.keychainManager = keychainManager
        self.mediaKeyManager = mediaKeyManager
        self.launchAtLoginManager = launchAtLoginManager
        self.diagnosticLogger = diagnosticLogger
        self.arylicClient = arylicClient
        self.reachabilityProbe = reachabilityProbe
        self.rootAccess = rootAccess ?? RootAccessService(keychain: keychainManager)
        self.userIdleSeconds = userIdleSeconds
        self.panelCareGraceDelay = panelCareGraceDelay
        self.panelCarePollInterval = panelCarePollInterval
        self.panelCareHistoryStore = panelCareHistoryStore
        self.panelCareHistory = panelCareHistoryStore?.load()
        self.now = now
        self.isScreenLocked = isScreenLocked
        self.sleepDebounceInterval = max(0, sleepDebounceInterval)
        self.wakeConnectInitialDelay = wakeConnectInitialDelay
        self.wakeConnectRetryDelay = wakeConnectRetryDelay
        self.wakeConnectMaxAttempts = max(1, wakeConnectMaxAttempts)
        self.wakeConnectTimeout = wakeConnectTimeout
        self.wakePortWait = wakePortWait
        
        setupCallbacks()
        loadConfiguration()
        loadArylicConfiguration()
    }
    #endif
    
    /// Convenience initializer with default implementations
    public convenience init() {
        self.init(
            webOSClient: WebOSClient(),
            wolService: WOLService(),
            powerManager: PowerManager(),
            keychainManager: KeychainManager(),
            mediaKeyManager: MediaKeyManager(),
            launchAtLoginManager: LaunchAtLoginManager(),
            diagnosticLogger: DiagnosticLogger(),
            reachabilityProbe: TCPReachabilityProbe(),
            userIdleSeconds: {
                // ~0 asks for any input event type.
                CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0) ?? .null)
            },
            panelCareHistoryStore: UserDefaultsPanelCareHistoryStore(),
            isScreenLocked: {
                let session = CGSessionCopyCurrentDictionary() as? [String: Any]
                return session?["CGSSessionScreenIsLocked"] as? Bool ?? false
            }
        )

        if UserDefaults.standard.bool(forKey: mediaKeyEnabledKey) {
            self.isMediaKeyControlEnabled = true
        }
    }
    
    // MARK: - Configuration
    
    /// Save TV configuration to UserDefaults
    public func saveConfiguration(_ config: TVConfiguration) throws {
        let data = try JSONEncoder().encode(config)
        UserDefaults.standard.set(data, forKey: configurationKey)
        self.configuration = config
        rootAccess.configurationDidChange()
        configurationDidChange?(config)
        logger.info("Configuration saved for \(config.name)")
    }
    
    /// Changes the saved configuration in place. Views use this instead of rebuilding the whole
    /// value, so a field added later is never reset by a form that does not know about it.
    public func updateConfiguration(_ mutate: (inout TVConfiguration) -> Void) throws {
        guard var config = configuration else {
            throw LGTVError.tvNotFound
        }
        mutate(&config)
        guard config != configuration else { return }
        try saveConfiguration(config)
    }

    /// Clear TV configuration from UserDefaults
    public func clearConfiguration() throws {
        UserDefaults.standard.removeObject(forKey: configurationKey)
        self.configuration = nil
        // The record belongs to that TV; another one's count would read as a refresh.
        panelCareHistory = nil
        panelCareHistoryStore?.save(nil)
        rootAccess.configurationDidChange()
        configurationDidChange?(nil)
        logger.info("Configuration cleared")
    }
    
    // MARK: - Connection
    
    /// Connect to the configured TV. This is the user-initiated path: it may raise the pairing
    /// prompt on the TV again after an earlier refusal.
    public func connect() async throws {
        pairingRequiresUser = false
        userDisconnected = false
        try await connectSharingInFlightAttempt()
    }

    /// Connect on behalf of automation. Refuses while pairing needs the user, so a TV that
    /// rejected pairing is not prompted again by a retry loop.
    private func connectAutomatically() async throws {
        guard !pairingRequiresUser else {
            throw LGTVError.actionSuppressed("Pairing needs your attention. Choose Connect to pair with the TV again.")
        }
        try await connectSharingInFlightAttempt()
    }

    private func connectSharingInFlightAttempt() async throws {
        if let connectTask {
            logDiagnostic(
                level: "info",
                category: "TVController",
                message: "Joining in-flight TV connection",
                metadata: ["connectionState": "\(connectionState)"]
            )
            try await connectTask.value
            return
        }

        let task = Task { @MainActor in
            try await self.performConnect()
        }

        connectTaskID &+= 1
        let taskID = connectTaskID
        connectTask = task
        defer {
            if connectTaskID == taskID {
                connectTask = nil
            }
        }

        try await task.value
    }

    private func performConnect() async throws {
        guard let config = configuration else {
            throw LGTVError.tvNotFound
        }
        
        logger.info("Connecting to \(config.name)")
        logDiagnostic(level: "info", category: "TVController", message: "Connecting to TV", metadata: ["connectionState": "\(connectionState)"])
        
        do {
            try await webOSClient.connect(to: config) { [weak self] state in
                Task { @MainActor in
                    self?.applyWebOSConnectionState(state)
                }
            }
        } catch let error as LGTVError where error == .pairingRejected || error == .pairingTimeout {
            pairingRequiresUser = true
            syncConnectionStateFromWebOSClient()
            logDiagnostic(level: "error", category: "TVController", message: "Pairing failed - automatic connects paused until the user reconnects", metadata: ["error": error.localizedDescription])
            throw error
        }

        guard webOSClient.connectionState.isConnected else {
            syncConnectionStateFromWebOSClient()
            throw LGTVError.webosError("Connection still in progress")
        }

        await requestDeviceDetailsCommands()
        
        #if LOCAL_ARYLIC_BUILD
        // Refresh Arylic status if target is Arylic
        if volumeControlTarget == .arylic && isArylicVolumeControlEnabled {
            await refreshArylicStatus()
        }
        #endif
    }
    
    /// Disconnect because the user asked to. The app stays disconnected until the user connects
    /// again or an automation trigger (Mac wake, opening the menu) calls for the TV.
    public func disconnect() {
        userDisconnected = true
        reconnectTask?.cancel()
        reconnectTask = nil
        dropConnection()
    }

    /// Drops the socket after a change that invalidates it (such as a new address) and lets
    /// reconnect supervision bring it back.
    public func resetConnection() {
        userDisconnected = false
        dropConnection()
    }

    /// Closes the connection without recording a user decision. Automation uses this.
    private func dropConnection() {
        connectTask?.cancel()
        connectTask = nil
        tvReportedStandby = false
        webOSClient.disconnect()
        connectionState = .disconnected
    }

    /// Reacts to a UI or system event according to `PowerPolicy`.
    @discardableResult
    public func handleAutomationTrigger(_ trigger: PowerPolicy.Trigger) -> Task<Void, Never>? {
        guard let config = configuration else { return nil }

        suspendedAutomation = governor.trippedKinds()
        let decision = PowerPolicy.decision(for: trigger, config: config, isConnected: connectionState.isConnected)
        logDiagnostic(level: "info", category: "TVController", message: "Automation trigger", metadata: [
            "trigger": trigger.rawValue,
            "decision": "\(decision)",
            "connectionState": "\(connectionState)",
            "wakeWithMac": "\(config.wakeWithMac)",
            "wakeOnMenuOpen": "\(config.wakeOnMenuOpen)"
        ])

        switch decision {
        case .wake:
            return startWakeRecovery(reason: trigger.rawValue)
        case .reconnectOnly:
            return Task { @MainActor [weak self] in
                await self?.reconnectIfReachable(reason: trigger.rawValue)
            }
        case .nothing:
            return nil
        }
    }

    /// Lets automation that the governor suspended run again.
    public func resetSuspendedAutomation() {
        governor.reset()
        suspendedAutomation = []
        logDiagnostic(level: "warning", category: "TVController", message: "Suspended automation reset by user")
    }
    
    /// Attempt to connect on app startup with retry logic
    public func autoConnectOnStartup() async {
        guard let config = configuration, config.autoConnectOnLaunch else { return }
        
        logger.info("Auto-connecting to TV on startup")
        
        pairingRequiresUser = false

        // Retry up to 3 times with increasing delays
        for attempt in 1...3 {
            if pairingRequiresUser { break }
            do {
                try await connectAutomatically()
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
        ensureReconnectSupervision()
    }
    
    /// Wake TV via Wake-on-LAN
    public func wake() async throws {
        guard let config = configuration else {
            throw LGTVError.tvNotFound
        }
        
        logger.info("Sending WOL to \(config.name)")
        logDiagnostic(level: "info", category: "TVController", message: "Sending Wake-on-LAN", metadata: tvIdentityMetadata(for: config))
        try await wolService.sendWakeRequest(to: config)
        logDiagnostic(level: "info", category: "TVController", message: "Wake-on-LAN packets sent", metadata: tvIdentityMetadata(for: config))
    }

    /// Ensure the configured TV is powered and its display panel is on when automation says it should be available.
    public func ensureTVAwake(reason: String, requiresWakePreference: Bool = true) async {
        guard let config = configuration else {
            logger.info("Skipping TV awake recovery - no TV configured")
            logDiagnostic(level: "info", category: "TVController", message: "TV awake recovery skipped - no configuration", metadata: ["reason": reason])
            return
        }

        // A TV this app switched off for a pixel refresh is always brought back, whatever the
        // wake setting: the setting is about following the Mac, not about undoing our own action.
        if requiresWakePreference && !config.wakeWithMac && !tvIsOffForPixelRefresh {
            logger.info("Skipping TV awake recovery - wake automation disabled")
            logDiagnostic(level: "info", category: "TVController", message: "TV awake recovery skipped - wake automation disabled", metadata: wakeMetadata(reason: reason, config: config))
            return
        }

        if isWakeInProgress {
            logger.info("Skipping TV awake recovery - recovery already in progress")
            logDiagnostic(level: "info", category: "TVController", message: "Wake attempt ignored - already in progress", metadata: wakeMetadata(reason: reason, config: config))
            return
        }

        // A wake that got this far is wanted; a refresh in progress gives way to it.
        endPixelRefreshWindow(outcome: "interrupted by \(reason)", resumeHeldWake: false)
        tvIsOffForPixelRefresh = false
        presenceWatchTask?.cancel()
        presenceWatchTask = nil

        isWakeInProgress = true
        userDisconnected = false
        defer {
            isWakeInProgress = false
            releaseConnectionIfTVIsInStandby()
            ensureReconnectSupervision()
        }

        // A connect already under way (possibly with the pairing prompt on screen) is joined, not
        // restarted: tearing it down would cancel the prompt and raise a second one.
        if connectionState.isTransitioning, let connectTask {
            logDiagnostic(level: "info", category: "TVController", message: "TV awake recovery waiting for in-flight connection", metadata: wakeMetadata(reason: reason, config: config))
            _ = try? await connectTask.value
        }

        if pairingRequiresUser {
            logDiagnostic(level: "warning", category: "TVController", message: "TV awake recovery skipped - pairing needs the user", metadata: wakeMetadata(reason: reason, config: config))
            return
        }

        logger.info("Ensuring TV is awake for reason: \(reason)")
        logDiagnostic(level: "info", category: "TVController", message: "TV awake recovery started", metadata: wakeMetadata(reason: reason, config: config))

        // Connected before this trigger, as opposed to connected by the quiet check below.
        let wasConnectedAtStart = connectionState.isConnected

        do {
            // A TV whose control port answers may already be on. Connect quietly and look
            // before sending a wake: a TV found showing a picture is someone's to keep, so
            // neither its power nor its input is touched.
            if !connectionState.isConnected, await isTVReachable(config) {
                logDiagnostic(level: "info", category: "TVController", message: "TV reachable before wake - connecting to check its state", metadata: wakeMetadata(reason: reason, config: config))
                try? await connectAutomatically()
                if pairingRequiresUser { return }
            }

            if connectionState.isConnected {
                let outcome = await ensureConnectedScreenIsOn(reason: reason, config: config)
                switch outcome {
                case .screenOnSent:
                    await performPostWakeActions(for: config, reason: reason)
                    return
                case .alreadyAwake, .skipped:
                    return
                case .turningOff where !isSomeoneAtTheMac(trigger: reason):
                    return
                case .standby where wasConnectedAtStart && !isSomeoneAtTheMac(trigger: reason):
                    // "Active Standby" is both what a TV reports while its pixel refresher runs
                    // and its ordinary standby when it keeps the network up, and a session can
                    // stay connected through either for as long as the TV is off. The state
                    // cannot tell them apart, so the person decides: with nobody at the Mac a
                    // possible refresh is left to finish; anyone who is there gets the display.
                    logDiagnostic(level: "warning", category: "TVController", message: "TV in standby with nobody at the Mac - left alone", metadata: wakeMetadata(reason: reason, config: config))
                    watchForSomeoneReturning()
                    return
                case .needsPowerOn, .standby, .turningOff, .connectionLost:
                    break
                }
            }

            // A wake sent while the TV is still switching off can be lost, so a TV that is
            // still off afterwards gets one more.
            for round in 1...Self.wakeRounds {
                guard permit(.powerOn, reason: reason) else { return }

                dropConnection()
                logWakeDiagnostics(reason: reason, config: config)
                try await sendWakePackets(config: config, reason: reason)
                try await connectAfterWake(reason: reason, config: config)

                switch await ensureConnectedScreenIsOn(reason: reason, config: config) {
                case .needsPowerOn, .standby, .turningOff:
                    guard round < Self.wakeRounds else { return }
                    logDiagnostic(level: "warning", category: "TVController", message: "TV still off after a wake - sending another", metadata: wakeMetadata(reason: reason, config: config))
                    try await Task.sleep(for: wakeConnectRetryDelay)
                case .skipped:
                    return
                case .alreadyAwake, .screenOnSent, .connectionLost:
                    // Reaching here means the TV was off or unreachable and this app turned it on.
                    await performPostWakeActions(for: config, reason: reason)
                    return
                }
            }
        } catch is CancellationError {
            logDiagnostic(level: "info", category: "TVController", message: "TV awake recovery cancelled", metadata: wakeMetadata(reason: reason, config: config))
        } catch {
            logger.error("Failed to ensure TV is awake: \(error.localizedDescription)")
            logDiagnostic(level: "error", category: "TVController", message: "Failed to ensure TV is awake", metadata: wakeMetadata(reason: reason, config: config, additional: ["error": error.localizedDescription]))
        }
    }

    /// After a TV in standby was left alone because nobody was at the Mac: wakes it as soon as
    /// someone is. Without this, a person who arrives after the trigger and causes no new one
    /// (no password to unlock, display already awake) would sit in front of a dark TV.
    private func watchForSomeoneReturning() {
        guard let userIdleSeconds else { return }
        presenceWatchTask?.cancel()
        presenceWatchTask = Task { @MainActor [weak self] in
            while true {
                guard let interval = self.map({ min($0.panelCarePollInterval, .seconds(5)) }) else { return }
                do {
                    try await Task.sleep(for: interval)
                } catch {
                    return
                }
                guard let self, !self.isMacAsleep, !self.userDisconnected else { return }
                if userIdleSeconds() < PanelCarePolicy.presenceThreshold {
                    self.presenceWatchTask = nil
                    self.startWakeRecovery(reason: PowerPolicy.Trigger.userRequested.rawValue)
                    return
                }
            }
        }
    }

    /// Whether this wake trigger shows a person at the Mac, by the same rule that decides
    /// whether a wake may interrupt a pixel refresh.
    private func isSomeoneAtTheMac(trigger reason: String) -> Bool {
        let trigger = PowerPolicy.Trigger(rawValue: reason) ?? .userRequested
        let idle = userIdleSeconds?() ?? 0
        return PanelCarePolicy.wakeDecision(trigger: trigger, userIdleSeconds: idle) == .proceed
    }

    @discardableResult
    internal func startWakeRecovery(reason: String) -> Task<Void, Never> {
        isMacAsleep = false
        handleDowntimeEnded()

        if let started = pixelRefreshStartedAt {
            let idle = userIdleSeconds?() ?? 0
            let elapsed = Date().timeIntervalSince(started)
            if elapsed < PanelCarePolicy.maximumRefreshWindow, !isSomeoneAtTheMac(trigger: reason) {
                heldWakeReason = reason
                logDiagnostic(level: "info", category: "PanelCare", message: "Wake held until the pixel refresh finishes", metadata: [
                    "reason": reason,
                    "userIdleSeconds": String(Int(idle)),
                    "secondsIntoRefresh": String(Int(elapsed))
                ])
                return wakeRecoveryTask ?? Task {}
            }
        }

        if isWakeRecoveryQueued || isWakeInProgress {
            if let config = configuration {
                logDiagnostic(level: "info", category: "TVController", message: "Wake attempt ignored - already in progress", metadata: wakeMetadata(reason: reason, config: config))
            } else {
                logDiagnostic(level: "info", category: "TVController", message: "TV awake recovery skipped - no configuration", metadata: ["reason": reason])
            }
            return wakeRecoveryTask ?? Task {}
        }

        isWakeRecoveryQueued = true
        let task = Task(priority: .userInitiated) { @MainActor [weak self] in
            guard let self else { return }
            self.isWakeRecoveryQueued = false
            await self.ensureTVAwake(reason: reason)
        }
        wakeRecoveryTask = task
        return task
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
        #if LOCAL_ARYLIC_BUILD
        if isArylicVolumeControlEnabled && volumeControlTarget == .arylic {
            guard let client = arylicClient else {
                logger.error("Arylic client not configured")
                throw LGTVError.tvNotFound
            }
            do {
                try await client.volumeUp()
                await refreshArylicStatus()
                logger.info("Arylic volume increased")
            } catch {
                logger.error("Failed to increase Arylic volume: \(error.localizedDescription)")
                logDiagnostic(level: "error", category: "TVController", message: "Failed to increase Arylic volume", metadata: ["error": error.localizedDescription])
                throw error
            }
            return
        }
        #endif
        try await webOSClient.sendCommand(.volumeUp)
    }
    
    /// Decrease volume
    public func volumeDown() async throws {
        #if LOCAL_ARYLIC_BUILD
        if isArylicVolumeControlEnabled && volumeControlTarget == .arylic {
            guard let client = arylicClient else {
                logger.error("Arylic client not configured")
                throw LGTVError.tvNotFound
            }
            do {
                try await client.volumeDown()
                await refreshArylicStatus()
                logger.info("Arylic volume decreased")
            } catch {
                logger.error("Failed to decrease Arylic volume: \(error.localizedDescription)")
                logDiagnostic(level: "error", category: "TVController", message: "Failed to decrease Arylic volume", metadata: ["error": error.localizedDescription])
                throw error
            }
            return
        }
        #endif
        try await webOSClient.sendCommand(.volumeDown)
    }
    
    /// Set specific volume level
    public func setVolume(_ level: Int) async throws {
        let clampedLevel = max(0, min(100, level))
        #if LOCAL_ARYLIC_BUILD
        if isArylicVolumeControlEnabled && volumeControlTarget == .arylic {
            guard let client = arylicClient else {
                logger.error("Arylic client not configured")
                throw LGTVError.tvNotFound
            }
            do {
                try await client.setVolume(clampedLevel)
                self.volume = clampedLevel
                logger.info("Arylic volume set to \(clampedLevel)")
            } catch {
                logger.error("Failed to set Arylic volume: \(error.localizedDescription)")
                logDiagnostic(level: "error", category: "TVController", message: "Failed to set Arylic volume", metadata: ["error": error.localizedDescription])
                throw error
            }
            return
        }
        #endif

        guard soundOutput.supportsVolumeSlider else {
            logger.info("Ignoring absolute volume set for sound output \(self.soundOutput.displayName)")
            logDiagnostic(
                level: "info",
                category: "TVController",
                message: "Ignored absolute volume set for unsupported sound output",
                metadata: [
                    "requestedVolume": "\(clampedLevel)",
                    "soundOutput": soundOutput.displayName,
                    "soundOutputRaw": soundOutput.rawValue
                ]
            )
            return
        }

        try await webOSClient.sendCommand(.setVolume(clampedLevel))
        self.volume = clampedLevel
    }
    
    /// Toggle mute
    public func toggleMute() async throws {
        #if LOCAL_ARYLIC_BUILD
        if isArylicVolumeControlEnabled && volumeControlTarget == .arylic {
            guard let client = arylicClient else {
                logger.error("Arylic client not configured")
                throw LGTVError.tvNotFound
            }
            let newMuteState = !isMuted
            do {
                try await client.setMute(newMuteState)
                isMuted = newMuteState
                logger.info("Arylic mute toggled to \(newMuteState)")
            } catch {
                logger.error("Failed to toggle Arylic mute: \(error.localizedDescription)")
                logDiagnostic(level: "error", category: "TVController", message: "Failed to toggle Arylic mute", metadata: ["error": error.localizedDescription])
                throw error
            }
            return
        }
        #endif
        // Decided before the request: the TV's own update can arrive while it is in flight.
        let target = !isMuted
        try await webOSClient.sendCommand(target ? .mute : .unmute)
        isMuted = target
    }
    
    #if LOCAL_ARYLIC_BUILD
    /// Refresh volume and mute state from Arylic device
    public func refreshArylicStatus() async {
        guard isArylicVolumeControlEnabled,
              volumeControlTarget == .arylic,
              let client = arylicClient else {
            return
        }
        
        do {
            let status = try await client.getPlayerStatus()
            self.volume = status.volume
            self.isMuted = status.isMuted
            logger.info("Refreshed Arylic status: volume=\(status.volume), muted=\(status.isMuted)")
            logDiagnostic(level: "info", category: "TVController", message: "Refreshed Arylic status", metadata: ["volume": "\(status.volume)", "isMuted": "\(status.isMuted)"])
        } catch {
            logger.error("Failed to refresh Arylic status: \(error.localizedDescription)")
            logDiagnostic(level: "error", category: "TVController", message: "Failed to refresh Arylic status", metadata: ["error": error.localizedDescription])
        }
    }
    #endif
    
    // MARK: - Input Control
    
    /// Switch to specified input
    public func switchInput(_ input: TVInputType) async throws {
        try await webOSClient.sendCommand(.setInput(input.rawValue))
        currentInput = input
        foreground = .input(input)
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
            logDiagnostic(level: "warning", category: "Diagnostics", message: "Diagnostic logging enabled", metadata: deviceDetailsMetadata())
        } else {
            logDiagnostic(level: "warning", category: "Diagnostics", message: "Diagnostic logging disabled", metadata: deviceDetailsMetadata())
            diagnosticLogger.disable()
        }

        updateDiagnosticCaptureSchedule()

        if enabled && diagnosticLogger.isDebugMode {
            capturePeriodicDiagnostics()
        }
    }

    public func setDiagnosticDebugMode(_ enabled: Bool) {
        diagnosticLogger.setDebugMode(enabled)
        updateDiagnosticCaptureSchedule()
        logDiagnostic(level: enabled ? "info" : "warning", category: "Diagnostics", message: "Diagnostic debug mode \(enabled ? "enabled" : "disabled")", metadata: deviceDetailsMetadata())

        if enabled && diagnosticLogger.isEnabled {
            capturePeriodicDiagnostics()
        }
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
        do {
            try await webOSClient.sendCommand(.setDeviceInfo(inputId: input.rawValue, icon: icon, label: label))
        } catch LGTVError.commandFailed(let message) {
            // Current firmware answers "401 insufficient permissions" on the pairing connection.
            logDiagnostic(level: "info", category: "TVController", message: "Input label not writable over the pairing connection; using a privileged call", metadata: ["error": message])
            try await privilegedCalls.invokePrivileged(
                "luna://com.webos.service.eim/setDeviceInfo",
                parameters: ["id": input.rawValue, "icon": "\(icon).png", "label": label]
            )
        }
        capabilities?.inputIcons[input.rawValue] = "\(icon).png"
        logger.info("Set PC mode \(enabled ? "enabled" : "disabled") for \(input.rawValue)")
    }
    
    // MARK: - Picture Settings

    /// The TV's current picture mode (for the content type currently playing).
    public func readPictureMode() async throws -> String {
        try await privilegedCalls.readPictureMode()
    }

    public func setPictureMode(_ mode: String) async throws {
        try await privilegedCalls.setPictureMode(mode)
    }

    /// Whether the TV labels the given input as a PC, from a fresh input list. Nil when the TV
    /// would not say, so callers do not "correct" something they cannot see.
    public func isPCMode(inputID: String) async -> Bool? {
        await refreshInputList()
        guard let icon = capabilities?.inputIcons[inputID] else { return nil }
        return TVInputInfo.iconIndicatesPC(icon)
    }

    /// Asks for the input list over the pairing connection, and through the root shell when
    /// that does not deliver one.
    private func refreshInputList() async {
        let before = capabilities?.inputs
        capabilities?.inputs = []
        try? await webOSClient.sendCommand(.getInputList)
        if capabilities?.inputs.isEmpty == false { return }

        if rootAccess.isUsable, let inputs = try? await rootAccess.inputList(), !inputs.isEmpty {
            applyInputList(inputs)
        } else {
            // No fresh answer either way. Keep the names for the pickers, but report the PC
            // label as unknown rather than repeat a stale value.
            capabilities?.inputs = before ?? []
            capabilities?.inputIcons = [:]
        }
    }

    private func applyInputList(_ inputs: [TVInputInfo]) {
        if capabilities == nil {
            capabilities = TVCapabilities()
        }
        capabilities?.inputs = inputs
        capabilities?.inputIcons = Dictionary(inputs.map { ($0.id, $0.icon) }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: - Panel Care

    /// Reads the panel's maintenance state through the root shell. Returns false when the TV
    /// could not be asked (its shell takes a while to come up after it powers on).
    @discardableResult
    public func refreshPanelCare() async -> Bool {
        #if UX_TESTING_APP
        return true
        #else
        guard rootAccess.isUsable else {
            panelCare = nil
            return true
        }
        do {
            let status = try await rootAccess.panelCareStatus()
            if pixelRefreshStartedAt == nil {
                logRefreshOutcomeIfPending(status)
            }
            if status != panelCare {
                logDiagnostic(level: "info", category: "PanelCare", message: "Panel-care state", metadata: [
                    "panelHours": "\(status.panelHours)",
                    "refreshCount": "\(status.refreshCount)",
                    "longRefreshCount": "\(status.longRefreshCount)",
                    "isRefreshDue": "\(status.isRefreshDue)"
                ])
            }
            panelCare = status
            recordPanelCareHistory(for: status)
            return true
        } catch {
            logDiagnostic(level: "info", category: "PanelCare", message: "Panel-care state not available", metadata: ["error": error.localizedDescription])
            return false
        }
        #endif
    }

    /// Says whether the refresh the app made room for ran. Judged only once the quiet period
    /// is over: the TV keeps answering for several minutes while it refreshes, with its count
    /// unchanged until it has finished.
    private func logRefreshOutcomeIfPending(_ status: PanelCareStatus) {
        guard let before = refreshCountBeforeQuietPeriod else { return }
        refreshCountBeforeQuietPeriod = nil
        let ran = status.refreshCount > before
        logDiagnostic(level: ran ? "info" : "warning", category: "PanelCare", message: ran ? "Pixel refresh ran while the TV was off" : "The TV did not run a pixel refresh while it was off", metadata: [
            "refreshCountBefore": "\(before)",
            "refreshCountAfter": "\(status.refreshCount)",
            "isRefreshDue": "\(status.isRefreshDue)"
        ])
    }

    private func recordPanelCareHistory(for status: PanelCareStatus) {
        let updated = PanelCareHistory.updated(panelCareHistory, with: status, at: now())
        guard updated != panelCareHistory else { return }
        if let refresh = updated.lastRefresh, refresh != panelCareHistory?.lastRefresh {
            logDiagnostic(level: "info", category: "PanelCare", message: "Pixel refresh seen", metadata: [
                "refreshCount": "\(updated.refreshCount)",
                "panelHours": "\(refresh.panelHours)"
            ])
        }
        panelCareHistory = updated
        panelCareHistoryStore?.save(updated)
    }

    /// Reads the panel-care state after a connect, trying again if the shell is not up yet.
    /// Without this the app keeps showing the state from before the TV was switched off.
    private func refreshPanelCareAfterConnect() {
        panelCareRetryTask?.cancel()
        panelCareRetryTask = Task { @MainActor [weak self] in
            for delay in [Duration.zero, .seconds(30), .seconds(120), .seconds(600)] {
                do {
                    try await Task.sleep(for: delay)
                } catch {
                    return
                }
                guard let self, self.connectionState.isConnected else { return }
                if await self.refreshPanelCare() { return }
            }
        }
    }

    private func handleDowntimeBegan(_ reason: String, lockNotified: Bool) {
        if lockNotified {
            isMacLocked = true
        }
        guard configuration?.refreshPixelsDuringDowntime == true, pixelRefreshStartedAt == nil, downtimeTask == nil else { return }

        logDiagnostic(level: "info", category: "PanelCare", message: "Mac downtime began", metadata: ["reason": reason])
        downtimeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                // A quick lock-and-unlock should not switch the TV off.
                try await Task.sleep(for: self.panelCareGraceDelay)
            } catch {
                return
            }
            self.downtimeTask = nil
            await self.powerOffForPixelRefreshIfDue(reason: reason)
        }
    }

    /// macOS is asked directly where possible: it posts no lock notification when the lock comes
    /// from the display going to sleep, which is the usual way a Mac ends up locked.
    private var macIsLocked: Bool {
        isScreenLocked?() ?? isMacLocked
    }

    private func handleDowntimeEnded(unlocked: Bool = false) {
        if unlocked {
            isMacLocked = false
        }
        downtimeTask?.cancel()
        downtimeTask = nil
    }

    private func powerOffForPixelRefreshIfDue(reason: String) async {
        guard let config = configuration else { return }

        if connectionState.isConnected {
            await refreshPanelCare()
            try? await webOSClient.sendCommand(.getCurrentForegroundAppInfo)
        }

        let isWithinAllowedHours = config.panelCareSchedule.allows(now())
        let decision = PanelCarePolicy.powerOffDecision(
            isEnabled: config.refreshPixelsDuringDowntime,
            isMacLocked: macIsLocked,
            isWithinAllowedHours: isWithinAllowedHours,
            status: panelCare,
            isConnected: connectionState.isConnected,
            foreground: foreground,
            preferredInput: config.preferredInput
        )
        logDiagnostic(level: "info", category: "PanelCare", message: "Downtime decision", metadata: [
            "reason": reason,
            "decision": "\(decision)",
            "isMacLocked": "\(macIsLocked)",
            "foreground": foreground.diagnosticDescription,
            "isRefreshDue": panelCare.map { "\($0.isRefreshDue)" } ?? "unknown",
            "connectionState": "\(connectionState)"
        ])

        if config.refreshPixelsDuringDowntime, !isWithinAllowedHours {
            waitForAllowedHours(config.panelCareSchedule)
            return
        }

        guard decision == .powerOff, permit(.powerOff, reason: "pixelRefresh") else { return }

        do {
            try await powerOff()
        } catch {
            logDiagnostic(level: "error", category: "PanelCare", message: "Could not switch the TV off for a pixel refresh", metadata: ["error": error.localizedDescription])
            return
        }
        tvIsOffForPixelRefresh = true
        dropConnection()

        // The Mac may have been unlocked while the TV was answering. That unlock's own wake
        // saw a TV that was still on, so the display is given back here.
        guard macIsLocked else {
            logDiagnostic(level: "warning", category: "PanelCare", message: "Mac unlocked while the TV was switching off - waking it again")
            startWakeRecovery(reason: PowerPolicy.Trigger.screenUnlock.rawValue)
            return
        }
        beginPixelRefreshWindow(reason: reason)
    }

    /// A Mac locked before the set hours begin is looked at again when they do. Unlocking or
    /// waking cancels this along with the rest of the downtime handling.
    private func waitForAllowedHours(_ schedule: PanelCareSchedule) {
        let current = now()
        guard macIsLocked, downtimeTask == nil, let start = schedule.nextStart(after: current) else { return }
        logDiagnostic(level: "info", category: "PanelCare", message: "Waiting for the set hours", metadata: [
            "seconds": String(Int(start.timeIntervalSince(current)))
        ])
        downtimeTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(start.timeIntervalSince(current)))
                // The same grace as a lock, so someone at the lock screen can get in first.
                guard let grace = self?.panelCareGraceDelay else { return }
                try await Task.sleep(for: grace)
            } catch {
                return
            }
            guard let self else { return }
            self.downtimeTask = nil
            await self.powerOffForPixelRefreshIfDue(reason: "setHoursBegan")
        }
    }

    /// Starts the quiet period: no reconnects and no unattended wakes until the TV reports the
    /// refresh done, stops answering, or the window runs out.
    private func beginPixelRefreshWindow(reason: String) {
        pixelRefreshStartedAt = Date()
        refreshCountBeforeQuietPeriod = panelCare?.refreshCount
        reconnectTask?.cancel()
        reconnectTask = nil
        logDiagnostic(level: "info", category: "PanelCare", message: "TV switched off for a pixel refresh", metadata: ["reason": reason])

        refreshMonitorTask?.cancel()
        refreshMonitorTask = Task { @MainActor [weak self] in
            var unanswered = 0
            while true {
                guard let interval = self?.panelCarePollInterval else { return }
                do {
                    try await Task.sleep(for: interval)
                } catch {
                    return
                }
                guard let self, let started = self.pixelRefreshStartedAt else { return }

                if Date().timeIntervalSince(started) >= PanelCarePolicy.maximumRefreshWindow {
                    self.endPixelRefreshWindow(outcome: "window elapsed")
                    return
                }
                if self.isMacAsleep { continue }

                if await self.refreshPanelCare() {
                    unanswered = 0
                    if let status = self.panelCare, !status.isRefreshDue {
                        self.endPixelRefreshWindow(outcome: "refresh completed")
                        self.logRefreshOutcomeIfPending(status)
                        return
                    }
                } else {
                    // The TV goes fully to sleep when it has finished.
                    unanswered += 1
                    if unanswered >= 3 {
                        self.endPixelRefreshWindow(outcome: "TV stopped answering")
                        return
                    }
                }
            }
        }
    }

    private func endPixelRefreshWindow(outcome: String, resumeHeldWake: Bool = true) {
        guard let started = pixelRefreshStartedAt else { return }
        pixelRefreshStartedAt = nil
        refreshMonitorTask?.cancel()
        refreshMonitorTask = nil
        let heldReason = heldWakeReason
        heldWakeReason = nil

        logDiagnostic(level: "info", category: "PanelCare", message: "Pixel refresh quiet period ended", metadata: [
            "outcome": outcome,
            "seconds": String(Int(Date().timeIntervalSince(started))),
            "heldWake": heldReason ?? "none"
        ])

        if resumeHeldWake, let heldReason, !isMacAsleep {
            startWakeRecovery(reason: heldReason)
        } else {
            ensureReconnectSupervision()
        }
    }

    /// Lets other automation (Display Lock) draw on the same loop guard as power automation.
    public func permitAutomaticAction(_ kind: ActionGovernor.Kind, reason: String) -> Bool {
        permit(kind, reason: reason)
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

    #if UX_TESTING_APP
    enum UXScenario: String, CaseIterable {
        case connected, appInFront, disconnected, pairingNeeded, connectionLost, automationPaused, noTV, rooted, pixelRefresh
    }

    /// Seed stable UI state for the regular-window UX validation build without writing user defaults.
    func applyUXTestingFixture(_ scenario: UXScenario = .connected) {
        var config = TVConfiguration(
            name: "LG C2",
            ipAddress: "192.168.88.24",
            macAddress: "AA:BB:CC:DD:EE:FF",
            preferredInput: TVInputType.hdmi1.rawValue,
            autoConnectOnLaunch: false,
            wakeWithMac: true,
            sleepWithMac: true,
            switchInputOnWake: true,
            enablePCMode: true,
            wakeBroadcastAddress: "192.168.88.255",
            wakePort: 9,
            wakeTimeoutSeconds: 90
        )
        config.displayLock = DisplayLockProfile(
            isEnabled: true,
            mode: DisplayModeSpec(pixelWidth: 3840, pixelHeight: 2160, pointWidth: 3840, pointHeight: 2160, refreshRate: 120),
            hdrEnabled: true,
            enforcePCMode: true,
            pictureMode: "game"
        )
        if scenario == .rooted || scenario == .pixelRefresh {
            config.refreshPixelsDuringDowntime = true
            config.rootAccess = RootAccessSettings(isEnabled: true, trustedHostKeyFingerprint: "SHA256:Zm9yLXNjcmVlbnNob3RzLW9ubHktbm90LWEta2V5")
        }

        configuration = scenario == .noTV ? nil : config
        rootAccess.configurationDidChange()
        pairingRequiresUser = scenario == .pairingNeeded
        suspendedAutomation = scenario == .automationPaused ? [.powerOn, .inputSwitch] : []

        switch scenario {
        case .disconnected, .pairingNeeded, .noTV, .pixelRefresh:
            connectionState = .disconnected
        case .connectionLost:
            connectionState = .error(LGTVError.connectionFailed("The TV stopped responding"))
        default:
            connectionState = .connected
        }

        let fixtureCapabilities = TVCapabilities(
            modelName: "HE_DTV_W22O_AFABATAA",
            chipType: "W22O",
            modelYear: 2022,
            webOSVersion: "webOSTV 7.0",
            usesSSL: true
        )
        fixtureCapabilities.displayModel = "OLED42C24LA"
        fixtureCapabilities.firmwareVersion = "03.33.85"
        fixtureCapabilities.inputs = [
            TVInputInfo(id: "HDMI_1", label: "PC", icon: "pc.png", isConnected: true),
            TVInputInfo(id: "HDMI_2", label: "PlayStation", icon: "game.png", isConnected: true),
            TVInputInfo(id: "HDMI_3", label: "HDMI 3", icon: "hdmi.png", isConnected: false),
            TVInputInfo(id: "HDMI_4", label: "HDMI 4", icon: "hdmi.png", isConnected: false)
        ]
        capabilities = fixtureCapabilities
        volume = 32
        isMuted = false
        foreground = scenario == .appInFront ? .app("netflix") : .input(.hdmi1)
        currentInput = foreground.input
        panelCare = scenario == .rooted || scenario == .pixelRefresh
            ? PanelCareStatus(panelHours: 6133, refreshCount: 424, longRefreshCount: 11, isRefreshDue: true, refreshIntervalHours: 4, longRefreshIntervalHours: 500)
            : nil
        panelCareHistory = PanelCareHistory(refreshCount: 424, lastRefresh: .init(panelHours: 6127, observedAt: Date().addingTimeInterval(-20 * 3_600)))
        pixelRefreshStartedAt = scenario == .pixelRefresh ? Date().addingTimeInterval(-180) : nil
        soundOutput = .tvSpeaker
        isMediaKeyControlEnabled = false
    }
    #endif
    
    // MARK: - Private Methods
    
    private func setupCallbacks() {
        rootAccess.configurationProvider = { [weak self] in self?.configuration }
        rootAccess.trustHostKey = { [weak self] fingerprint in
            try? self?.updateConfiguration { $0.rootAccess.trustedHostKeyFingerprint = fingerprint }
        }
        rootAccess.log = { [weak self] level, message, metadata in
            self?.logDiagnostic(level: level, category: "RootAccess", message: message, metadata: metadata)
        }

        // WebOS capability updates
        webOSClient.setCapabilityCallback { [weak self] capabilities in
            MainActor.assumeIsolated {
                self?.capabilities = capabilities
            }
        }
        
        // The client always calls back on the main actor. Applying state synchronously means a
        // caller that awaits a confirmed request sees the resulting state as soon as it resumes.
        webOSClient.setInputChangeCallback { [weak self] input in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.currentInput = input
                self.setForeground(.input(input))
            }
        }

        webOSClient.setForegroundChangeCallback { [weak self] foreground in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.currentInput = foreground.input
                self.setForeground(foreground)
            }
        }

        webOSClient.setLogCallback { [weak self] level, message, metadata in
            self?.logDiagnostic(level: level, category: "WebOSClient", message: message, metadata: metadata)
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
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.capabilities == nil {
                    self.capabilities = TVCapabilities()
                }
                self.capabilities?.inputIcons = inputIcons
            }
        }
        
        webOSClient.setPowerStateChangeCallback { [weak self] status in
            Task { @MainActor [weak self] in
                self?.handlePowerStateChange(status)
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
            self?.startWakeRecovery(reason: "systemWake")
            self?.ensureReconnectSupervision()
        }
        
        powerManagerMutable.onSleep = { [weak self] in
            guard let self = self else { return }
            Task { @MainActor [weak self] in
                await self?.handleMacSleep()
            }
        }
        
        powerManagerMutable.onScreenWake = { [weak self] in
            self?.startWakeRecovery(reason: "screenWake")
        }

        powerManagerMutable.onScreenUnlock = { [weak self] in
            self?.handleDowntimeEnded(unlocked: true)
            self?.startWakeRecovery(reason: "screenUnlock")
        }

        powerManagerMutable.onScreenLock = { [weak self] in
            self?.handleDowntimeBegan("screenLocked", lockNotified: true)
        }

        powerManagerMutable.onScreenSleep = { [weak self] in
            self?.handleDowntimeBegan("displaySlept", lockNotified: false)
        }

        
        // Start monitoring
        powerManager.startMonitoring()
    }
    
    private func loadConfiguration() {
        defer { rootAccess.configurationDidChange() }
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
    
    #if LOCAL_ARYLIC_BUILD
    private func loadArylicConfiguration() {
        // Load Arylic volume control enabled flag
        isArylicVolumeControlEnabled = UserDefaults.standard.bool(forKey: arylicVolumeControlEnabledKey)
        
        // Load volume control target
        if let targetString = UserDefaults.standard.string(forKey: volumeControlTargetKey),
           let target = VolumeControlTarget(rawValue: targetString) {
            volumeControlTarget = target
        }
        
        // Load Arylic settings
        if let data = UserDefaults.standard.data(forKey: arylicSettingsKey) {
            do {
                let settings = try JSONDecoder().decode(ArylicSettings.self, from: data)
                arylicSettings = settings
                arylicClient = ArylicVolumeClient(settings: settings)
                logger.info("Loaded Arylic settings: \(settings.host):\(settings.port)")
            } catch {
                logger.error("Failed to decode Arylic settings: \(error.localizedDescription)")
            }
        }
    }
    #endif
    
    private func sendWakePackets(config: TVConfiguration, reason: String) async throws {
        do {
            logDiagnostic(level: "info", category: "TVController", message: "Wake-on-LAN attempt", metadata: wakeMetadata(reason: reason, config: config, additional: ["attempt": "1"]))
            try await wake()
        } catch {
            logger.warning("Wake-on-LAN failed: \(error.localizedDescription)")
            logDiagnostic(level: "warning", category: "TVController", message: "Wake-on-LAN attempt failed", metadata: wakeMetadata(reason: reason, config: config, additional: ["attempt": "1", "error": error.localizedDescription]))
            throw error
        }
    }

    private func connectAfterWake(reason: String, config: TVConfiguration) async throws {
        var lastError: Error?
        let clock = ContinuousClock()
        let startedAt = clock.now
        let timeout = wakeTimeout(for: config)
        let deadline = startedAt.advanced(by: timeout)
        var attempt = 1

        while attempt <= wakeConnectMaxAttempts && clock.now < deadline {
            // Mac sleep cancels wake recovery; stop here instead of waking a TV for a sleeping Mac.
            if attempt == 1 {
                try await Task.sleep(for: wakeConnectInitialDelay)
            } else {
                try await Task.sleep(for: wakeConnectRetryDelay)
            }
            try await waitForControlPort(config, until: deadline)

            let elapsedSeconds = durationSecondsString(startedAt.duration(to: clock.now))
            let timeoutSeconds = durationSecondsString(timeout)
            let metadata = wakeMetadata(
                reason: reason,
                config: config,
                additional: [
                    "attempt": "\(attempt)",
                    "elapsedSeconds": elapsedSeconds,
                    "wakeTimeoutSeconds": timeoutSeconds
                ]
            )

            do {
                logger.info("Wake reconnect attempt \(attempt)")
                logDiagnostic(level: "info", category: "TVController", message: "Wake reconnect attempt", metadata: metadata)
                try await connectAutomatically()
                logger.info("Wake reconnect succeeded on attempt \(attempt)")
                let successMetadata = wakeMetadata(
                    reason: reason,
                    config: config,
                    additional: [
                        "attempt": "\(attempt)",
                        "elapsedSeconds": elapsedSeconds,
                        "wakeTimeoutSeconds": timeoutSeconds
                    ]
                )
                logDiagnostic(level: "info", category: "TVController", message: "Wake reconnect succeeded", metadata: successMetadata)
                return
            } catch {
                lastError = error
                logger.warning("Wake reconnect attempt \(attempt) failed: \(error.localizedDescription)")
                logDiagnostic(level: "warning", category: "TVController", message: "Wake reconnect attempt failed", metadata: wakeMetadata(reason: reason, config: config, additional: [
                    "attempt": "\(attempt)",
                    "elapsedSeconds": elapsedSeconds,
                    "wakeTimeoutSeconds": timeoutSeconds,
                    "error": error.localizedDescription
                ]))
                if pairingRequiresUser || Task.isCancelled {
                    throw error
                }
                resetConnectionAfterWakeFailure(reason: reason, config: config, attempt: attempt)
            }

            attempt += 1
        }

        throw lastError ?? LGTVError.webosError("Failed to reconnect after wake")
    }

    /// A TV starting from deep standby takes tens of seconds to open its control port, and a
    /// connection tried before then spends its whole timeout finding that out. Watching the port
    /// costs a second at most and lets the connection start the moment the TV can take it.
    private func waitForControlPort(_ config: TVConfiguration, until deadline: ContinuousClock.Instant) async throws {
        guard reachabilityProbe != nil else { return }
        let clock = ContinuousClock()
        let giveUpAt = min(deadline, clock.now.advanced(by: wakePortWait))

        while clock.now < giveUpAt {
            if await isTVReachable(config) { return }
            try await Task.sleep(for: min(.milliseconds(500), clock.now.duration(to: giveUpAt)))
        }
    }

    private func ensureConnectedScreenIsOn(reason: String, config: TVConfiguration) async -> ScreenRecoveryOutcome {
        do {
            let powerStatus = try await webOSClient.getPowerStatus()
            logDiagnostic(level: "info", category: "TVController", message: "TV power state observed", metadata: wakeMetadata(reason: reason, config: config, additional: powerStatus.diagnosticMetadata))

            switch powerStatus.normalizedState {
            case .active, .screenOnInProgress, .screenSaver:
                logDiagnostic(level: "info", category: "TVController", message: "TV already awake", metadata: wakeMetadata(reason: reason, config: config, additional: powerStatus.diagnosticMetadata))
                return .alreadyAwake
            case .screenOff:
                return await turnScreenOnAfterPowerCheck(reason: reason, config: config, powerStatus: powerStatus)
            case .off:
                logDiagnostic(level: "info", category: "TVController", message: "TV power state indicates power-on is needed", metadata: wakeMetadata(reason: reason, config: config, additional: powerStatus.diagnosticMetadata))
                return .needsPowerOn
            case .turningOff:
                logDiagnostic(level: "info", category: "TVController", message: "TV is turning off", metadata: wakeMetadata(reason: reason, config: config, additional: powerStatus.diagnosticMetadata))
                return .turningOff
            case .activeStandby:
                // Reported both while the pixel refresher runs and by TVs that keep their network
                // up in standby. The caller decides: before a wake it means "send the wake";
                // after one it means "leave it be".
                logDiagnostic(level: "warning", category: "TVController", message: "TV in active standby", metadata: wakeMetadata(reason: reason, config: config, additional: powerStatus.diagnosticMetadata))
                return .standby
            case .unknown:
                logger.warning("TV power state unknown; sending screen-on as fallback")
                logDiagnostic(level: "warning", category: "TVController", message: "TV power state unknown - sending screen on", metadata: wakeMetadata(reason: reason, config: config, additional: powerStatus.diagnosticMetadata))
                return await turnScreenOnAfterPowerCheck(reason: reason, config: config, powerStatus: powerStatus)
            }
        } catch {
            logger.warning("Failed to query TV power state: \(error.localizedDescription)")
            logDiagnostic(level: "warning", category: "TVController", message: "Failed to query TV power state - sending screen on", metadata: wakeMetadata(reason: reason, config: config, additional: ["error": error.localizedDescription]))
            if !webOSClient.connectionState.isConnected {
                syncConnectionStateFromWebOSClient()
                logDiagnostic(level: "info", category: "TVController", message: "TV connection lost during power check - wake reconnect required", metadata: wakeMetadata(reason: reason, config: config, additional: ["error": error.localizedDescription]))
                return .connectionLost
            }
            return await turnScreenOnAfterPowerCheck(reason: reason, config: config, powerStatus: nil)
        }
    }

    private func turnScreenOnAfterPowerCheck(reason: String, config: TVConfiguration, powerStatus: TVPowerStatus?) async -> ScreenRecoveryOutcome {
        do {
            logger.info("Turning TV screen on")
            var metadata = wakeMetadata(reason: reason, config: config)
            if let powerStatus {
                metadata.merge(powerStatus.diagnosticMetadata) { _, new in new }
            }
            logDiagnostic(level: "info", category: "TVController", message: "Turning TV screen on", metadata: metadata)
            try await screenOn()
            logDiagnostic(level: "info", category: "TVController", message: "TV screen-on command sent", metadata: metadata)
            return .screenOnSent
        } catch {
            logger.warning("Failed to turn TV screen on: \(error.localizedDescription)")
            logDiagnostic(level: "warning", category: "TVController", message: "Failed to turn TV screen on", metadata: wakeMetadata(reason: reason, config: config, additional: ["error": error.localizedDescription]))
            if !webOSClient.connectionState.isConnected {
                syncConnectionStateFromWebOSClient()
                logDiagnostic(level: "info", category: "TVController", message: "TV connection lost during screen-on - wake reconnect required", metadata: wakeMetadata(reason: reason, config: config, additional: ["error": error.localizedDescription]))
                return .connectionLost
            }
            // The TV answered and declined, which is what a screen that is already on does.
            if case LGTVError.commandFailed = error {
                return .alreadyAwake
            }
            return .skipped
        }
    }

    private func performPostWakeActions(for config: TVConfiguration, reason: String) async {
        // The input list says whether the Mac's input already carries the PC label. Ask for it
        // now; right after a wake the session bootstrap may not have delivered it yet.
        // Unknown counts as "already set", so the label is never written blind on every wake.
        var preferredInputIsPCMode = true
        if config.enablePCMode {
            preferredInputIsPCMode = await isPCMode(inputID: config.preferredInput) ?? true
        }

        let actions = PowerPolicy.postWakeActions(
            config: config,
            foreground: foreground,
            preferredInputIsPCMode: preferredInputIsPCMode
        )

        logDiagnostic(level: "info", category: "TVController", message: "Post-wake decision", metadata: wakeMetadata(reason: reason, config: config, additional: [
            "foreground": foreground.diagnosticDescription,
            "preferredInputIsPCMode": "\(preferredInputIsPCMode)",
            "switchInput": "\(actions.switchInput)",
            "setPCMode": "\(actions.setPCMode)"
        ]))

        guard let input = TVInputType(rawValue: config.preferredInput) else { return }

        if actions.switchInput, permit(.inputSwitch, reason: reason) {
            do {
                try await switchInput(input)
            } catch {
                logger.warning("Failed to switch input after wake: \(error.localizedDescription)")
                logDiagnostic(level: "warning", category: "TVController", message: "Failed to switch input after wake", metadata: ["error": error.localizedDescription, "preferredInput": config.preferredInput])
            }
        }

        if actions.setPCMode, permit(.tvSettingWrite, reason: reason) {
            do {
                logger.info("Setting PC mode for \(config.preferredInput)")
                try await setPCMode(for: input, enabled: true)
            } catch {
                logger.warning("Failed to set PC mode after wake: \(error.localizedDescription)")
                logDiagnostic(level: "warning", category: "TVController", message: "Failed to set PC mode after wake", metadata: ["error": error.localizedDescription, "preferredInput": config.preferredInput])
            }
        }
    }
    
    private func handleMacSleep() async {
        isMacAsleep = true
        reconnectTask?.cancel()
        reconnectTask = nil
        // Sleep has its own power-off below; a pending lock-time check must not fire on wake.
        downtimeTask?.cancel()
        downtimeTask = nil
        presenceWatchTask?.cancel()
        presenceWatchTask = nil

        if isWakeInProgress || isWakeRecoveryQueued {
            wakeRecoveryTask?.cancel()
            logDiagnostic(level: "info", category: "TVController", message: "Mac sleeping - cancelling TV awake recovery")
        }

        guard let config = configuration else {
            logDiagnostic(level: "info", category: "TVController", message: "TV sleep skipped - no configuration")
            return
        }

        guard config.sleepWithMac else {
            logDiagnostic(level: "info", category: "TVController", message: "TV sleep skipped - sleep automation disabled", metadata: tvIdentityMetadata(for: config))
            return
        }
        
        // Debounce: prevent duplicate sleep attempts within 10 seconds
        let now = Date()
        let timeSinceLastSleep = now.timeIntervalSince(lastSleepExecution)
        if timeSinceLastSleep < sleepDebounceInterval {
            logger.info("Skipping sleep - debounced (last execution \(String(format: "%.1f", timeSinceLastSleep))s ago)")
            logDiagnostic(level: "info", category: "TVController", message: "Sleep attempt debounced", metadata: ["timeSinceLastSleep": "\(String(format: "%.1f", timeSinceLastSleep))s"])
            return
        }
        lastSleepExecution = now

        // Ask the TV what is in front right now rather than trusting the last subscription update.
        if connectionState.isConnected {
            try? await webOSClient.sendCommand(.getCurrentForegroundAppInfo)
        }

        let decision = PowerPolicy.sleepDecision(config: config, isConnected: connectionState.isConnected, foreground: foreground)
        var metadata = tvIdentityMetadata(for: config)
        metadata["foreground"] = foreground.diagnosticDescription
        metadata["connectionState"] = "\(connectionState)"
        metadata["decision"] = "\(decision)"

        switch decision {
        case .leaveOn(let reason):
            logger.info("Skipping TV sleep - \(reason)")
            metadata["currentInput"] = currentInput?.displayName ?? foreground.diagnosticDescription
            logDiagnostic(level: "info", category: "TVController", message: "Skipping TV sleep - different input", metadata: metadata)
            dropConnection()
        case .skip(let reason):
            logDiagnostic(level: "warning", category: "TVController", message: "TV sleep skipped - \(reason)", metadata: metadata)
            dropConnection()
        case .powerOff:
            guard permit(.powerOff, reason: "macSleep") else {
                dropConnection()
                return
            }
            logger.info("Mac sleeping - turning off TV")
            logDiagnostic(level: "info", category: "TVController", message: "Mac sleeping - turning off TV", metadata: metadata)
            do {
                try await powerOff()
                if config.refreshPixelsDuringDowntime, panelCare?.isRefreshDue == true {
                    beginPixelRefreshWindow(reason: "macSleep")
                }
            } catch {
                logger.error("Failed to turn off TV: \(error.localizedDescription)")
                logDiagnostic(level: "error", category: "TVController", message: "Failed to turn off TV", metadata: ["error": error.localizedDescription])
            }
            dropConnection()
        }
    }

    // MARK: - Reconnect Supervision

    private func setForeground(_ newValue: TVForeground) {
        guard foreground != newValue else { return }
        logDiagnostic(level: "info", category: "TVController", message: "TV foreground changed", metadata: ["from": foreground.diagnosticDescription, "to": newValue.diagnosticDescription])
        foreground = newValue
        foregroundDidChange?(newValue)
    }

    private func handleConnectionStateChange() {
        if connectionState.isConnected {
            reconnectTask?.cancel()
            reconnectTask = nil
            lastConnectedAt = .now
            Task { @MainActor [weak self] in
                await self?.refreshRootBackedDetails()
            }
            return
        }
        // Whatever the last session's TV reported says nothing about the next one.
        tvReportedStandby = false
        if connectionState.isTransitioning { return }
        ensureReconnectSupervision()
    }

    /// Fills in what only the root shell can tell: software version and panel-care state.
    private func refreshRootBackedDetails() async {
        #if UX_TESTING_APP
        // Fixture state only; never open a shell to the placeholder address.
        return
        #else
        if rootAccess.status == .notChecked {
            await rootAccess.refresh()
        }
        guard let root = rootAccess.capabilities, connectionState.isConnected else { return }

        if capabilities == nil {
            capabilities = TVCapabilities()
        }
        if let platformModel = root.platformModel {
            capabilities?.modelName = platformModel
            if let parsed = TVCapabilities.parseChipType(from: platformModel) {
                capabilities?.chipType = parsed.chip
                capabilities?.modelYear = parsed.year
            }
        }
        if let productName = root.productName {
            capabilities?.webOSVersion = productName
        }
        if let firmwareVersion = root.firmwareVersion {
            capabilities?.firmwareVersion = firmwareVersion
        }
        refreshPanelCareAfterConnect()
        #endif
    }

    private func isTVReachable(_ config: TVConfiguration) async -> Bool {
        guard let reachabilityProbe else { return false }
        return await reachabilityProbe.isReachable(host: config.ipAddress, timeout: .seconds(1))
    }

    private func reconnectIfReachable(reason: String) async {
        guard let config = configuration,
              !connectionState.isConnected,
              !connectionState.isTransitioning,
              !isWakeInProgress,
              pixelRefreshStartedAt == nil,
              !pairingRequiresUser else { return }
        userDisconnected = false

        guard await isTVReachable(config) else {
            logDiagnostic(level: "info", category: "TVController", message: "Reconnect skipped - TV not reachable", metadata: ["reason": reason])
            return
        }

        do {
            try await connectAutomatically()
            logDiagnostic(level: "info", category: "TVController", message: "Reconnected", metadata: ["reason": reason])
        } catch {
            logDiagnostic(level: "warning", category: "TVController", message: "Reconnect failed", metadata: ["reason": reason, "error": error.localizedDescription])
        }
    }

    private func handlePowerStateChange(_ status: TVPowerStatus) {
        guard connectionState.isConnected else { return }
        let isInStandby = status.normalizedState == .activeStandby || status.normalizedState == .off
        if isInStandby != tvReportedStandby {
            logDiagnostic(level: "info", category: "TVController", message: "TV power state changed", metadata: status.diagnosticMetadata)
        }
        tvReportedStandby = isInStandby
        releaseConnectionIfTVIsInStandby()
    }

    /// A TV in standby with its network up keeps its session open. Holding it would show the
    /// app as connected to a TV that is off, and keep Display Lock judging a picture nobody
    /// sees, so the session is let go and looked for again later, at a pace that cannot keep
    /// the TV from sleeping. A wake in progress is left to finish: the TV reports standby for
    /// a moment on its way up.
    private func releaseConnectionIfTVIsInStandby() {
        guard tvReportedStandby, connectionState.isConnected, !isWakeInProgress else { return }
        logDiagnostic(level: "info", category: "TVController", message: "TV went into standby - releasing the connection")
        reconnectDelayOverride = Self.standbyRecheckDelay
        dropConnection()
    }

    /// Starts the background reconnect loop if one is needed and allowed. The loop never wakes
    /// the TV and never raises a pairing prompt more than once.
    private func ensureReconnectSupervision() {
        guard reachabilityProbe != nil,
              configuration != nil,
              reconnectTask == nil,
              !isMacAsleep,
              !pairingRequiresUser,
              !userDisconnected,
              pixelRefreshStartedAt == nil,
              !connectionState.isConnected else { return }

        // Start over only after a connection that lasted; one that dropped straight away
        // continues the backoff where it left off.
        if let lastConnectedAt, ContinuousClock.now - lastConnectedAt >= .seconds(60) {
            reconnectAttempt = 0
        } else if lastConnectedAt != nil {
            reconnectAttempt += 1
        }
        lastConnectedAt = nil

        logDiagnostic(level: "info", category: "TVController", message: "Reconnect supervision started", metadata: ["connectionState": "\(connectionState)", "attempt": "\(reconnectAttempt)"])

        reconnectTask = Task { @MainActor [weak self] in
            var attempt = self?.reconnectAttempt ?? 0
            while true {
                let delay = self?.reconnectDelayOverride ?? ReconnectSchedule.delay(forAttempt: attempt)
                self?.reconnectDelayOverride = nil
                do {
                    try await Task.sleep(for: delay)
                } catch {
                    return
                }
                guard let self, !Task.isCancelled else { return }

                guard let config = self.configuration,
                      !self.connectionState.isConnected,
                      !self.pairingRequiresUser,
                      !self.userDisconnected,
                      self.pixelRefreshStartedAt == nil,
                      !self.isMacAsleep else { break }
                self.reconnectAttempt = attempt

                if self.isWakeInProgress || self.connectionState.isTransitioning {
                    continue
                }

                guard await self.isTVReachable(config) else {
                    if ReconnectSchedule.shouldLog(attempt: attempt) {
                        self.logDiagnostic(level: "debug", category: "TVController", message: "Reconnect check - TV not reachable", metadata: ["attempt": "\(attempt)"])
                    }
                    attempt += 1
                    continue
                }
                guard !Task.isCancelled else { return }

                do {
                    try await self.connectAutomatically()
                    // The power subscription normally reports this by itself; asking covers a
                    // TV that does not answer it.
                    if let status = try? await self.webOSClient.getPowerStatus(),
                       status.normalizedState == .activeStandby || status.normalizedState == .off {
                        self.logDiagnostic(level: "info", category: "TVController", message: "Reconnected to a TV in standby - releasing", metadata: status.diagnosticMetadata)
                        self.reconnectDelayOverride = Self.standbyRecheckDelay
                        self.dropConnection()
                        return
                    }
                    self.logDiagnostic(level: "info", category: "TVController", message: "Reconnected after connection loss", metadata: ["attempt": "\(attempt)"])
                    break
                } catch {
                    self.logDiagnostic(level: "warning", category: "TVController", message: "Reconnect attempt failed", metadata: ["attempt": "\(attempt)", "error": error.localizedDescription])
                    attempt += 1
                }
            }
            if !Task.isCancelled {
                self?.reconnectTask = nil
            }
        }
    }

    /// Asks the governor whether an automatic action may run, and records a refusal where the
    /// user can see it.
    private func permit(_ kind: ActionGovernor.Kind, reason: String) -> Bool {
        let decision = governor.request(kind)
        suspendedAutomation = governor.trippedKinds()

        if case .tripped(let until) = decision {
            logger.error("Automation suspended to prevent a loop: \(kind.rawValue)")
            logDiagnostic(level: "error", category: "TVController", message: "Automation suspended to prevent a loop", metadata: [
                "kind": kind.rawValue,
                "reason": reason,
                "suspendedUntil": ISO8601DateFormatter().string(from: until)
            ])
            return false
        }
        return true
    }
    
    private func updateMediaKeyCapture() async {
        if isMediaKeyControlEnabled && connectionState.isConnected {
            if !mediaKeyManager.hasAccessibilityPermission {
                // The preference is kept: permission is lost on every ad-hoc rebuild, and
                // silently switching the setting off made users re-enable it each time.
                if !isMediaKeyPermissionMissing {
                    logger.warning("Volume keys inactive - Accessibility permission not granted")
                    logDiagnostic(level: "warning", category: "TVController", message: "Volume keys inactive - Accessibility permission not granted", metadata: appIdentityMetadata())
                }
                isMediaKeyPermissionMissing = true
                return
            }
            isMediaKeyPermissionMissing = false
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
        #if LOCAL_ARYLIC_BUILD
        let arylicTargeted = isArylicVolumeControlEnabled && volumeControlTarget == .arylic
        #else
        let arylicTargeted = false
        #endif
        guard connectionState.isConnected || arylicTargeted else { return }
        
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

    private var isWebOSConnectionReady: Bool {
        connectionState.isConnected && webOSClient.connectionState.isConnected
    }

    private func applyWebOSConnectionState(_ state: ConnectionState) {
        let clientState = webOSClient.connectionState
        guard state == clientState else {
            logger.debug("Ignoring stale WebOS state callback: \(state.description, privacy: .public); client is \(clientState.description, privacy: .public)")
            return
        }

        connectionState = state
    }

    private func syncConnectionStateFromWebOSClient() {
        let clientState = webOSClient.connectionState
        if connectionState != clientState {
            connectionState = clientState
        }
    }

    private func resetConnectionAfterWakeFailure(reason: String, config: TVConfiguration, attempt: Int) {
        if webOSClient.connectionState.isTransitioning {
            syncConnectionStateFromWebOSClient()
            logDiagnostic(
                level: "info",
                category: "TVController",
                message: "Wake reconnect preserved active registration",
                metadata: wakeMetadata(reason: reason, config: config, additional: ["attempt": "\(attempt)"])
            )
            return
        }

        dropConnection()
    }

    private func appIdentityMetadata() -> [String: String] {
        var metadata: [String: String] = [:]
        metadata["bundleIdentifier"] = Bundle.main.bundleIdentifier ?? "unknown"
        metadata["bundlePath"] = Bundle.main.bundleURL.path
        metadata["executablePath"] = Bundle.main.executableURL?.path ?? "unknown"
        return metadata
    }

    private func tvIdentityMetadata(for config: TVConfiguration) -> [String: String] {
        [
            "tvName": config.name,
            "ipAddress": config.ipAddress,
            "preferredInput": config.preferredInput
        ]
    }

    private func wakeMetadata(reason: String, config: TVConfiguration, additional: [String: String] = [:]) -> [String: String] {
        var metadata = tvIdentityMetadata(for: config)
        metadata["reason"] = reason
        metadata["connectionState"] = "\(connectionState)"
        metadata.merge(additional) { _, new in new }
        return metadata
    }

    private func logWakeDiagnostics(reason: String, config: TVConfiguration) {
        var metadata = wakeMetadata(reason: reason, config: config)
        metadata.merge(wolService.wakeDiagnostics(for: config)) { _, new in new }
        metadata["requiredTVSettings"] = metadata["requiredTVSettings"] ?? "TV On With Mobile / Turn On via Wi-Fi enabled; LG Connect Apps/Mobile App enabled; Quick Start+/Always Ready may affect standby behavior"
        metadata["networkStandbyLimit"] = metadata["networkStandbyLimit"] ?? "Cannot wake a TV from true deep-off, unplugged, or power-saving states without a standby network, CEC, or IR path"
        logDiagnostic(level: "info", category: "TVController", message: "Wake diagnostics snapshot", metadata: metadata)
    }

    private func wakeTimeout(for config: TVConfiguration) -> Duration {
        guard let configuredSeconds = config.wakeTimeoutSeconds, configuredSeconds > 0 else {
            return wakeConnectTimeout
        }
        return .seconds(configuredSeconds)
    }

    private func durationSecondsString(_ duration: Duration) -> String {
        let components = duration.components
        let seconds = Double(components.seconds) + (Double(components.attoseconds) / 1_000_000_000_000_000_000)
        return String(format: "%.1f", seconds)
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
        let metadata = deviceDetailsMetadata()

        guard connectionState.isConnected else {
            if metadata != lastPeriodicSnapshotMetadata {
                lastPeriodicSnapshotMetadata = metadata
                logDiagnostic(level: "debug", category: "TVController", message: "Skipped periodic capture - not connected", metadata: metadata)
            }
            return
        }

        if metadata != lastPeriodicSnapshotMetadata {
            lastPeriodicSnapshotMetadata = metadata
            logDiagnostic(level: "debug", category: "TVController", message: "Periodic device status snapshot", metadata: metadata)
        }

        Task { @MainActor in
            await requestDeviceDetailsCommands()
        }
    }

    private func requestDeviceDetailsCommands() async {
        guard await requestDeviceDetailCommand(.getCurrentForegroundAppInfo, failureMessage: "Failed to request foreground app info") else { return }
        guard await requestDeviceDetailCommand(.getInputList, failureMessage: "Failed to request input list") else { return }
        guard await requestDeviceDetailCommand(.getSoundOutput, failureMessage: "Failed to request sound output") else { return }
        _ = await requestDeviceDetailCommand(.getVolume, failureMessage: "Failed to request volume")
    }

    private func requestDeviceDetailCommand(_ command: WebOSCommand, failureMessage: String) async -> Bool {
        guard isWebOSConnectionReady else {
            syncConnectionStateFromWebOSClient()
            return false
        }

        do {
            try await webOSClient.sendCommand(command)
            return true
        } catch {
            if !webOSClient.connectionState.isConnected {
                syncConnectionStateFromWebOSClient()
            }
            logDiagnostic(level: "warning", category: "TVController", message: failureMessage, metadata: ["error": error.localizedDescription])
            return false
        }
    }
}
