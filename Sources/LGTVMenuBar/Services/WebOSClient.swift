import Foundation
import Network
import OSLog

@MainActor
public protocol WebOSClientProtocol {
    var connectionState: ConnectionState { get }
    func connect(to configuration: TVConfiguration, stateChangeCallback: @escaping @Sendable (ConnectionState) -> Void) async throws
    func disconnect()
    func sendCommand(_ command: WebOSCommand) async throws
    func setCapabilityCallback(_ callback: @escaping @Sendable (TVCapabilities) -> Void)
    func setInputChangeCallback(_ callback: @escaping @Sendable (TVInputType) -> Void)
    func setVolumeChangeCallback(_ callback: @escaping @Sendable (Int, Bool) -> Void)
    func setInputListCallback(_ callback: @escaping @Sendable ([String: String]) -> Void)
}

/// Custom URLSession delegate for accepting self-signed certificates
private final class InsecureURLSessionDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        // Accept self-signed certificates for local TV connections
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let serverTrust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

/// WebSocket client for communicating with LG WebOS TVs
@MainActor
final class WebOSClient: WebOSClientProtocol {
    private let logger = Logger(subsystem: "com.lgtvmenubar", category: "WebOSClient")
    
    /// WebSocket connection to the TV
    private var webSocketTask: URLSessionWebSocketTask?
    
    /// URL session for WebSocket connections
    private let urlSession: URLSession
    
    /// URL session for SSL connections with self-signed certificate support
    private let sslURLSession: URLSession
    
    /// Keychain manager for storing client keys
    private let keychainManager: KeychainManager
    
    /// Current connection state
    private var _connectionState = ConnectionState.disconnected
    
    /// TV configuration
    private var configuration: TVConfiguration?
    
    /// Callback for connection state changes
    private var stateChangeCallback: (@Sendable (ConnectionState) -> Void)?
    
    /// Callback for TV capability updates
    private var capabilityCallback: (@Sendable (TVCapabilities) -> Void)?
    
    /// Callback for TV input changes
    private var inputChangeCallback: (@Sendable (TVInputType) -> Void)?
    
    /// Callback for volume changes
    private var volumeChangeCallback: (@Sendable (Int, Bool) -> Void)?
    
    /// Callback for input list with icons
    private var inputListCallback: (@Sendable ([String: String]) -> Void)?
    
    /// Handshake completion flag
    private var handshakeCompleted = false
    
    /// Message counter for requests
    private var messageCounter = 1
    
    /// Pending requests awaiting responses
    private var pendingRequests: [String: CheckedContinuation<Any, Error>] = [:]
    
    /// Whether the current connection uses SSL
    private var usesSSL: Bool = false
    
    /// Connection timeout in seconds
    private let connectionTimeout: TimeInterval = 10.0
    
    /// Current connection state
    var connectionState: ConnectionState {
        return _connectionState
    }
    
    /// Initialize WebOSClient
    init(keychainManager: KeychainManager = KeychainManager()) {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 30
        self.urlSession = URLSession(configuration: configuration)
        
        // Create SSL session with custom delegate for self-signed certificates
        let sslConfiguration = URLSessionConfiguration.default
        sslConfiguration.timeoutIntervalForRequest = 10
        sslConfiguration.timeoutIntervalForResource = 30
        let delegate = InsecureURLSessionDelegate()
        self.sslURLSession = URLSession(configuration: sslConfiguration, delegate: delegate, delegateQueue: nil)
        
        self.keychainManager = keychainManager
        
        logger.info("WebOSClient initialized")
    }
    
    deinit {
        _connectionState = .disconnected
        webSocketTask?.cancel()
        webSocketTask = nil
    }
    
    /// Connect to the TV using WebSocket
    /// - Parameters:
    ///   - configuration: TV configuration containing connection details
    ///   - stateChangeCallback: Closure called when connection state changes
    /// - Throws: `LGTVError.webosError` if connection fails
    func connect(to configuration: TVConfiguration, stateChangeCallback: @escaping @Sendable (ConnectionState) -> Void) async throws {
        guard _connectionState == .disconnected else {
            logger.warning("Already connected or connecting")
            return
        }
        
        logger.info("Connecting to \(configuration.name) at \(configuration.ipAddress)")
        
        self.configuration = configuration
        self.stateChangeCallback = stateChangeCallback
        self._connectionState = .connecting
        
        stateChangeCallback(.connecting)
        
        // Connection strategy: Try SSL first (required for 2022+ TVs), fallback to non-SSL
        var lastError: Error?
        
        // Try SSL connection (wss:// on port 3001)
        do {
            logger.debug("Attempting SSL connection on port 3001")
            try await connectWithProtocol(ipAddress: configuration.ipAddress, useSSL: true)
            self.usesSSL = true
            self._connectionState = .connected
            stateChangeCallback(.connected)
            logger.info("\("Successfully connected via SSL", privacy: .public) to \(configuration.name)")
            return
        } catch {
            logger.debug("SSL connection failed: \(error.localizedDescription, privacy: .public), trying non-SSL")
            lastError = error
            // Clean up failed connection
            webSocketTask?.cancel()
            webSocketTask = nil
        }
        
        // Try non-SSL connection (ws:// on port 3000)
        do {
            logger.debug("Attempting non-SSL connection on port 3000")
            try await connectWithProtocol(ipAddress: configuration.ipAddress, useSSL: false)
            self.usesSSL = false
            self._connectionState = .connected
            stateChangeCallback(.connected)
            logger.info("\("Successfully connected via non-SSL", privacy: .public) to \(configuration.name)")
            return
        } catch {
            logger.error("Non-SSL connection also failed: \(error.localizedDescription, privacy: .public)")
            lastError = error
        }
        
        // Both connection attempts failed
        self._connectionState = .disconnected
        stateChangeCallback(.disconnected)
        throw LGTVError.webosError("Failed to connect to TV: \(lastError?.localizedDescription ?? "Unknown error")")
    }
    
    /// Connect to the TV using a specific protocol (SSL or non-SSL)
    /// - Parameters:
    ///   - ipAddress: IP address of the TV
    ///   - useSSL: Whether to use SSL (wss://) or not (ws://)
    /// - Throws: `LGTVError.webosError` if connection fails
    private func connectWithProtocol(ipAddress: String, useSSL: Bool) async throws {
        let port = useSSL ? 3001 : 3000
        let scheme = useSSL ? "wss" : "ws"
        
        guard let wsURL = URL(string: "\(scheme)://\(ipAddress):\(port)/") else {
            throw LGTVError.webosError("Invalid WebSocket URL")
        }
        
        // Create WebSocket task with appropriate session
        let session = useSSL ? sslURLSession : urlSession
        webSocketTask = session.webSocketTask(with: wsURL)
        webSocketTask?.resume()
        
        // Start message handling
        Task {
            await handleMessages()
        }
        
        // Perform handshake with timeout
        try await withTimeout(connectionTimeout) {
            try await self.performHandshake()
        }
        
        handshakeCompleted = true
    }
    
    /// Execute an async operation with a timeout
    /// - Parameters:
    ///   - timeout: Timeout duration in seconds
    ///   - operation: The async operation to execute
    /// - Returns: Result of the operation
    /// - Throws: Error if operation fails or times out
    private func withTimeout<T: Sendable>(_ timeout: TimeInterval, operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            // Add operation task
            group.addTask {
                try await operation()
            }
            
            // Add timeout task
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw LGTVError.webosError("Connection timeout")
            }
            
            // Return first result (operation or timeout)
            guard let result = try await group.next() else {
                throw LGTVError.webosError("Task group failed")
            }
            
            // Cancel remaining tasks
            group.cancelAll()
            
            return result
        }
    }
    
    /// Disconnect from the TV
    func disconnect() {
        guard _connectionState != .disconnected else {
            return
        }
        
        logger.info("\("Disconnecting from TV", privacy: .public)")
        
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        
        _connectionState = .disconnected
        handshakeCompleted = false
        
        // Fail all pending requests
        for (_, continuation) in pendingRequests {
            continuation.resume(throwing: LGTVError.webosError("Connection closed"))
        }
        pendingRequests.removeAll()
        
        stateChangeCallback?(.disconnected)
        
        logger.info("\("Disconnected from TV", privacy: .public)")
    }
    
    /// Send a command to the TV
    /// - Parameter command: Command to send
    /// - Throws: `LGTVError.webosError` if sending fails
    func sendCommand(_ command: WebOSCommand) async throws {
        guard _connectionState == .connected, handshakeCompleted else {
            throw LGTVError.webosError("Not connected to TV")
        }
        
        logger.debug("Sending command: \(String(describing: command))")
        
        do {
            let messageDict = try createCommandMessage(command)
            let data = try JSONSerialization.data(withJSONObject: messageDict)
            let string = String(data: data, encoding: .utf8)!
            
            webSocketTask?.send(.string(string)) { error in
                if let error = error {
                    self.logger.error("Failed to send command: \(error.localizedDescription, privacy: .public)")
                }
            }
            
        } catch {
            throw LGTVError.webosError("Failed to send command: \(error.localizedDescription)")
        }
    }
    
    /// Set callback for TV capability updates
    /// - Parameter callback: Closure called when capabilities are updated
    func setCapabilityCallback(_ callback: @escaping @Sendable (TVCapabilities) -> Void) {
        self.capabilityCallback = callback
    }
    
    /// Set callback for TV input changes
    /// - Parameter callback: Closure called when input changes
    func setInputChangeCallback(_ callback: @escaping @Sendable (TVInputType) -> Void) {
        self.inputChangeCallback = callback
    }
    
    /// Set callback for volume changes
    /// - Parameter callback: Closure called when volume changes (volume level, isMuted)
    func setVolumeChangeCallback(_ callback: @escaping @Sendable (Int, Bool) -> Void) {
        self.volumeChangeCallback = callback
    }
    
    /// Set callback for input list updates
    /// - Parameter callback: Closure called when input list is received (inputId -> icon)
    func setInputListCallback(_ callback: @escaping @Sendable ([String: String]) -> Void) {
        self.inputListCallback = callback
    }
    
    // MARK: - Private Methods
    
    /// Perform handshake with the TV
    private func performHandshake() async throws {
        logger.debug("Performing handshake")
        
        // Check if we have a stored client key for this TV
        var existingClientKey: String?
        if let ipAddress = configuration?.ipAddress {
            existingClientKey = try? keychainManager.loadClientKey(for: ipAddress)
            if existingClientKey != nil {
                logger.debug("Found existing client key for \(ipAddress)")
            }
        }
        
        var payload: [String: Any] = [
            "forcePairing": false,
            "pairingType": "PROMPT",
            "manifest": [
                "manifestVersion": 1,
                "appVersion": "1.0",
                "signatures": [
                    [
                        "signature": "dummy_signature",
                        "signatureVersion": 1
                    ]
                ],
                "permissions": [
                    "LAUNCH",
                    "LAUNCH_WEBAPP",
                    "APP_TO_APP",
                    "CLOSE",
                    "TEST_OPEN",
                    "TEST_PROTECTED",
                    "CONTROL_AUDIO",
                    "CONTROL_DISPLAY",
                    "CONTROL_INPUT_JOYSTICK",
                    "CONTROL_INPUT_MEDIA_RECORDING",
                    "CONTROL_INPUT_MEDIA_PLAYBACK",
                    "CONTROL_INPUT_TV",
                    "CONTROL_POWER",
                    "READ_APP_STATUS",
                    "READ_INPUT_DEVICE_LIST",
                    "READ_NETWORK_STATE",
                    "READ_RUNNING_APPS",
                    "READ_TV_CHANNEL_LIST",
                    "WRITE_NOTIFICATION_TOAST",
                    "READ_SETTINGS",
                    "WRITE_SETTINGS",
                    "CONTROL_POINTER",
                    "CONTROL_MOUSE_AND_KEYBOARD",
                    "CONTROL_POWER_ON_SCREEN"
                ],
                "signerId": "com.lgtvmenubar",
                "appId": "com.lgtvmenubar.app"
            ]
        ]
        
        // Include client key if we have one
        if let clientKey = existingClientKey {
            payload["client-key"] = clientKey
        }
        
        let handshakeMessage: [String: Any] = [
            "id": "register_\(messageCounter)",
            "type": "register",
            "payload": payload
        ]
        
        let data = try JSONSerialization.data(withJSONObject: handshakeMessage)
        let string = String(data: data, encoding: .utf8)!
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            webSocketTask?.send(.string(string)) { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
        
        // Wait for handshake response
        try await waitForHandshakeResponse()
        
        logger.debug("Handshake completed")
    }
    
    /// Wait for handshake response
    private func waitForHandshakeResponse() async throws {
        // This would normally wait for a specific response message
        // For now, we'll simulate a short delay
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
    }
    
    /// Handle incoming WebSocket messages
    private func handleMessages() async {
        while _connectionState == .connecting || _connectionState == .connected {
            do {
                let message = try await webSocketTask?.receive()
                
                switch message {
                case .string(let string):
                    await handleMessage(string)
                case .data(let data):
                    if let string = String(data: data, encoding: .utf8) {
                        await handleMessage(string)
                    }
                case .none:
                    break
                @unknown default:
                    logger.warning("Unknown message type received")
                }
                
            } catch {
                logger.error("Error receiving message: \(error.localizedDescription, privacy: .public)")
                
                if _connectionState != .disconnected {
                    _connectionState = .error(error)
                    stateChangeCallback?(.error(error))
                }
                break
            }
        }
    }
    
    /// Handle a received message
    private func handleMessage(_ string: String) async {
        guard let data = string.data(using: .utf8),
              let messageDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            logger.warning("Failed to decode message: \(string)")
            return
        }
        
        let messageType = messageDict["type"] as? String ?? "unknown"
        logger.debug("Received message: \(messageType)")
        
        switch messageType {
        case "registered":
            await handleRegisteredMessage(messageDict)
        case "response":
            await handleResponseMessage(messageDict)
        case "push":
            await handlePushMessage(messageDict)
        default:
            logger.debug("Unhandled message type: \(messageType)")
        }
    }
    
    /// Handle registered message
    private func handleRegisteredMessage(_ messageDict: [String: Any]) async {
        logger.info("\("Successfully registered with TV", privacy: .public)")
        
        // Extract and save client key if present
        if let payload = messageDict["payload"] as? [String: Any],
           let clientKey = payload["client-key"] as? String,
           let ipAddress = configuration?.ipAddress {
            do {
                try keychainManager.saveClientKey(clientKey, for: ipAddress)
                logger.debug("Saved client key for \(ipAddress)")
            } catch {
                logger.error("Failed to save client key: \(error.localizedDescription, privacy: .public)")
            }
        }
        
        // Request TV capabilities
        try? await sendCommand(WebOSCommand.getForegroundAppInfo)
        try? await sendCommand(WebOSCommand.getInputList)
        
        // Query current foreground app immediately (one-time, not subscription)
        try? await sendCommand(WebOSCommand.getCurrentForegroundAppInfo)
        
        // Subscribe to volume changes (will push updates when volume changes)
        try? await sendCommand(WebOSCommand.subscribeVolume)
    }
    
    /// Handle response message
    private func handleResponseMessage(_ messageDict: [String: Any]) async {
        guard let payload = messageDict["payload"] as? [String: Any] else { return }
        
        // Check for volume data in response
        if let volume = payload["volume"] as? Int {
            let isMuted = payload["muted"] as? Bool ?? false
            volumeChangeCallback?(volume, isMuted)
            logger.debug("Volume update: \(volume), muted: \(isMuted)")
        }
        
        // Check for foreground app data (current input) in response
        if let appId = payload["appId"] as? String {
            if let inputType = mapAppIdToInputType(appId) {
                inputChangeCallback?(inputType)
                logger.debug("Current input from appId: \(appId) -> \(inputType.displayName)")
            }
        }
        
        // Check for input list data in response (from getInputList / getExternalInputList)
        if let devices = payload["devices"] as? [[String: Any]] {
            var inputIcons: [String: String] = [:]
            for device in devices {
                if let id = device["id"] as? String,
                   let icon = device["icon"] as? String {
                    inputIcons[id] = icon
                    logger.debug("Input \(id) has icon: \(icon)")
                }
            }
            if !inputIcons.isEmpty {
                inputListCallback?(inputIcons)
            }
        }
    }
    
    /// Handle push message
    private func handlePushMessage(_ messageDict: [String: Any]) async {
        guard let payload = messageDict["payload"] as? [String: Any] else { return }
        
        // Handle different push types
        if payload.keys.contains("foregroundAppInfo") {
            await handleForegroundAppUpdate(payload)
        } else if payload.keys.contains("inputSource") {
            await handleInputChange(payload)
        } else if payload.keys.contains("volume") {
            // Volume subscription push
            if let volume = payload["volume"] as? Int {
                let isMuted = payload["muted"] as? Bool ?? false
                volumeChangeCallback?(volume, isMuted)
                logger.debug("Volume push: \(volume), muted: \(isMuted)")
            }
        }
    }
    
    /// Handle foreground app update
    private func handleForegroundAppUpdate(_ payload: [String: Any]) async {
        // Update capabilities based on current app
        let capabilities = TVCapabilities()
        capabilities.usesSSL = self.usesSSL
        
        logger.debug("TV capabilities - SSL: \(self.usesSSL)")
        
        capabilityCallback?(capabilities)
        
        // Extract current input from foreground app info
        if let appId = payload["appId"] as? String {
            if let inputType = mapAppIdToInputType(appId) {
                inputChangeCallback?(inputType)
                logger.debug("Foreground app input: \(appId) -> \(inputType.displayName)")
            }
        }
    }
    
    /// Handle input change
    private func handleInputChange(_ payload: [String: Any]) async {
        // Extract input type from payload
        if let inputSource = payload["inputSource"] as? String {
            let inputType = mapInputSourceToType(inputSource)
            inputChangeCallback?(inputType)
        }
    }
    
    /// Map input source string to TVInputType
    private func mapInputSourceToType(_ inputSource: String) -> TVInputType {
        switch inputSource.lowercased() {
        case "hdmi_1", "hdmi1":
            return .hdmi1
        case "hdmi_2", "hdmi2":
            return .hdmi2
        case "hdmi_3", "hdmi3":
            return .hdmi3
        case "hdmi_4", "hdmi4":
            return .hdmi4
        case "dp_1", "displayport1":
            return .displayPort1
        case "dp_2", "displayport2":
            return .displayPort2
        case "usb_c_1", "usbc1":
            return .usbC1
        case "usb_c_2", "usbc2":
            return .usbC2
        default:
            return .hdmi1 // fallback
        }
    }
    
    /// Map WebOS app ID to TVInputType
    /// Returns nil if the app ID doesn't correspond to an input
    private func mapAppIdToInputType(_ appId: String) -> TVInputType? {
        // WebOS input app IDs follow pattern: com.webos.app.hdmi1, com.webos.app.hdmi2, etc.
        let lowercased = appId.lowercased()
        
        for inputType in TVInputType.allCases {
            if lowercased == inputType.appId.lowercased() {
                return inputType
            }
        }
        
        // Also handle alternative formats
        if lowercased.contains("hdmi1") || lowercased.contains("hdmi_1") {
            return .hdmi1
        } else if lowercased.contains("hdmi2") || lowercased.contains("hdmi_2") {
            return .hdmi2
        } else if lowercased.contains("hdmi3") || lowercased.contains("hdmi_3") {
            return .hdmi3
        } else if lowercased.contains("hdmi4") || lowercased.contains("hdmi_4") {
            return .hdmi4
        } else if lowercased.contains("dp1") || lowercased.contains("dp_1") || lowercased.contains("displayport1") {
            return .displayPort1
        } else if lowercased.contains("dp2") || lowercased.contains("dp_2") || lowercased.contains("displayport2") {
            return .displayPort2
        } else if lowercased.contains("usbc1") || lowercased.contains("usbc_1") || lowercased.contains("usb-c1") {
            return .usbC1
        } else if lowercased.contains("usbc2") || lowercased.contains("usbc_2") || lowercased.contains("usb-c2") {
            return .usbC2
        }
        
        return nil
    }
    
    /// Create command message
    private func createCommandMessage(_ command: WebOSCommand) throws -> [String: Any] {
        let id = "req_\(messageCounter)"
        messageCounter += 1
        
        var message: [String: Any] = [
            "id": id,
            "type": "request"
        ]
        
        switch command {
        case .getForegroundAppInfo:
            message["type"] = "subscribe"
            message["uri"] = "ssap://com.webos.applicationManager/getForegroundAppInfo"
        case .getCurrentForegroundAppInfo:
            message["uri"] = "ssap://com.webos.applicationManager/getForegroundAppInfo"
        case .getInputList:
            message["uri"] = "ssap://tv/getInputList"
        case .powerOn:
            message["uri"] = "ssap://system/turnOn"
        case .powerOff:
            message["uri"] = "ssap://system/turnOff"
        case .volumeUp:
            message["uri"] = "ssap://audio/volumeUp"
        case .volumeDown:
            message["uri"] = "ssap://audio/volumeDown"
        case .setVolume(let level):
            message["uri"] = "ssap://audio/setVolume"
            message["payload"] = ["volume": level]
        case .getVolume:
            message["uri"] = "ssap://audio/getVolume"
        case .subscribeVolume:
            message["type"] = "subscribe"
            message["uri"] = "ssap://audio/getVolume"
        case .mute:
            message["uri"] = "ssap://audio/mute"
        case .unmute:
            message["uri"] = "ssap://audio/unmute"
        case .setInput(let inputId):
            message["uri"] = "ssap://tv/switchInput"
            message["payload"] = ["inputId": inputId]
        case .screenOn:
            message["uri"] = "ssap://com.webos.service.tvpower/power/turnOnScreen"
        case .screenOff:
            message["uri"] = "ssap://com.webos.service.tvpower/power/turnOffScreen"
        case .setDeviceInfo(let inputId, let icon, let label):
            message["uri"] = "ssap://com.webos.service.eim/setDeviceInfo"
            message["payload"] = ["id": inputId, "icon": "\(icon).png", "label": label]
        }
        
        return message
    }
}