import Foundation
import Network
import OSLog

@MainActor
public protocol WebOSClientProtocol {
    var connectionState: ConnectionState { get }
    func connect(to configuration: TVConfiguration, stateChangeCallback: @escaping @Sendable (ConnectionState) -> Void) async throws
    func disconnect()
    /// Sends a command and waits for the TV to confirm it. Throws if the TV rejects it or stays silent.
    func sendCommand(_ command: WebOSCommand) async throws
    /// Sends an arbitrary SSAP request and returns the TV's confirmed reply.
    func request(uri: String, payload: [String: Any]?) async throws -> SSAPReply
    func getPowerStatus() async throws -> TVPowerStatus
    func setCapabilityCallback(_ callback: @escaping @Sendable (TVCapabilities) -> Void)
    func setInputChangeCallback(_ callback: @escaping @Sendable (TVInputType) -> Void)
    func setForegroundChangeCallback(_ callback: @escaping @Sendable (TVForeground) -> Void)
    func setVolumeChangeCallback(_ callback: @escaping @Sendable (Int, Bool) -> Void)
    func setInputListCallback(_ callback: @escaping @Sendable ([String: String]) -> Void)
    func setSoundOutputChangeCallback(_ callback: @escaping @Sendable (TVSoundOutput) -> Void)
    func setDiagnosticPayloadCallback(_ callback: @escaping (String, String) -> Void)
    /// Receives (level, message, metadata) for every connection lifecycle event.
    func setLogCallback(_ callback: @escaping (String, String, [String: String]) -> Void)
}

/// Custom URLSession delegate for accepting self-signed certificates
private final class InsecureURLSessionDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        // LG TVs present a self-signed certificate; the pairing key, not TLS, authenticates the TV.
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let serverTrust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

/// WebSocket (SSAP) client for LG webOS TVs.
///
/// Every request is correlated to its reply by id and bounded by a timeout, so callers learn
/// whether the TV actually accepted a command. Timeouts are driven by timers that resume the
/// waiting continuation directly; nothing here relies on task cancellation reaching a callback API.
@MainActor
final class WebOSClient: WebOSClientProtocol {

    struct Timeouts: Sendable {
        /// Time allowed for the TV to answer the registration message at all.
        var handshake: Duration = .seconds(10)
        /// Time allowed for the viewer to accept the on-screen pairing prompt.
        var pairingPrompt: Duration = .seconds(60)
        /// Time allowed for a reply to an ordinary request.
        var reply: Duration = .seconds(5)
        /// Interval between liveness checks on an idle connection.
        var keepAliveInterval: Duration = .seconds(45)

        init(
            handshake: Duration = .seconds(10),
            pairingPrompt: Duration = .seconds(60),
            reply: Duration = .seconds(5),
            keepAliveInterval: Duration = .seconds(45)
        ) {
            self.handshake = handshake
            self.pairingPrompt = pairingPrompt
            self.reply = reply
            self.keepAliveInterval = keepAliveInterval
        }
    }

    private struct PendingRequest {
        let uri: String
        let continuation: CheckedContinuation<SSAPReply, Error>
        let timeoutTask: Task<Void, Never>
    }

    private let logger = Logger(subsystem: "com.lgtvmenubar", category: "WebOSClient")

    private var webSocketTask: URLSessionWebSocketTask?
    private let urlSession: URLSession
    private let sslURLSession: URLSession
    private let keychainManager: KeychainManagerProtocol
    private let endpoints: [WebOSConnectionEndpoint]
    private let timeouts: Timeouts

    private var _connectionState = ConnectionState.disconnected

    /// Monotonic token used to ignore callbacks from stale socket attempts.
    private var connectionAttemptID: UInt64 = 0

    /// Bumped by `disconnect()` so an in-flight `connect()` stops instead of trying the next endpoint.
    private var cancelGeneration: UInt64 = 0

    private var configuration: TVConfiguration?
    private var stateChangeCallback: (@Sendable (ConnectionState) -> Void)?
    private var capabilityCallback: (@Sendable (TVCapabilities) -> Void)?
    private var inputChangeCallback: (@Sendable (TVInputType) -> Void)?
    private var foregroundChangeCallback: (@Sendable (TVForeground) -> Void)?
    private var volumeChangeCallback: (@Sendable (Int, Bool) -> Void)?
    private var inputListCallback: (@Sendable ([String: String]) -> Void)?
    private var soundOutputChangeCallback: (@Sendable (TVSoundOutput) -> Void)?
    private var diagnosticPayloadCallback: ((String, String) -> Void)?
    private var logCallback: ((String, String, [String: String]) -> Void)?

    private var handshakeCompleted = false
    private var messageCounter = 1
    private var pendingRequests: [String: PendingRequest] = [:]
    private var handshakeContinuation: CheckedContinuation<Void, Error>?
    private var handshakeTimeoutTask: Task<Void, Never>?
    private var keepAliveTask: Task<Void, Never>?
    private var bootstrapTask: Task<Void, Never>?
    private var usesSSL = false

    /// Capabilities accumulated for the current connection.
    private var capabilities = TVCapabilities()

    /// Optional test hook for observing connection state changes without a real socket.
    private var testStateChangeObserver: ((ConnectionState) -> Void)?

    /// Optional test hook for intercepting command sends without a live socket.
    private var testSendCommandHandler: ((WebOSCommand) async throws -> Void)?

    var connectionState: ConnectionState { _connectionState }

    init(
        keychainManager: KeychainManagerProtocol = KeychainManager(),
        endpoints: [WebOSConnectionEndpoint] = WebOSConnectionEndpoint.preferredOrder,
        timeouts: Timeouts = Timeouts()
    ) {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 30
        self.urlSession = URLSession(configuration: configuration)

        let sslConfiguration = URLSessionConfiguration.default
        sslConfiguration.timeoutIntervalForRequest = 10
        sslConfiguration.timeoutIntervalForResource = 30
        self.sslURLSession = URLSession(configuration: sslConfiguration, delegate: InsecureURLSessionDelegate(), delegateQueue: nil)

        self.keychainManager = keychainManager
        self.endpoints = endpoints
        self.timeouts = timeouts
    }

    // MARK: - Test Hooks

    internal func setTestStateChangeObserver(_ observer: @escaping (ConnectionState) -> Void) {
        self.testStateChangeObserver = observer
    }

    internal func setTestSendCommandHandler(_ handler: @escaping (WebOSCommand) async throws -> Void) {
        self.testSendCommandHandler = handler
    }

    internal func setConnectionStateForTesting(_ state: ConnectionState, handshakeCompleted: Bool) {
        self._connectionState = state
        self.handshakeCompleted = handshakeCompleted
    }

    internal func handleMessageForTesting(_ string: String) async {
        handleMessage(string)
    }

    @discardableResult
    internal func beginConnectionAttemptForTesting() -> UInt64 {
        beginConnectionAttempt()
    }

    internal func emitConnectionStateForTesting(_ state: ConnectionState, attemptID: UInt64) {
        publishConnectionState(state, attemptID: attemptID)
    }

    deinit {
        webSocketTask?.cancel()
    }

    // MARK: - Connection

    func connect(to configuration: TVConfiguration, stateChangeCallback: @escaping @Sendable (ConnectionState) -> Void) async throws {
        // A registration handshake in flight must not be reset: doing so re-raises the pairing prompt.
        if _connectionState == .connected || _connectionState.isTransitioning {
            logger.warning("Connection already active")
            return
        }

        if _connectionState != .disconnected {
            _ = beginConnectionAttempt()
            tearDownSocket(reason: LGTVError.webosError("Connection reset"))
        }

        log("info", "Connecting", ["host": configuration.ipAddress])

        self.configuration = configuration
        self.stateChangeCallback = stateChangeCallback
        let generation = cancelGeneration

        var lastError: Error?

        for endpoint in endpoints {
            let attemptID = beginConnectionAttempt()
            publishConnectionState(.connecting, attemptID: attemptID)

            do {
                try await connectWithProtocol(ipAddress: configuration.ipAddress, endpoint: endpoint, attemptID: attemptID)
                log("info", "Connected", ["scheme": endpoint.scheme, "port": "\(endpoint.port)"])
                return
            } catch {
                lastError = error
                log("warning", "Endpoint failed", ["scheme": endpoint.scheme, "port": "\(endpoint.port)", "error": error.localizedDescription])

                guard generation == cancelGeneration else {
                    // disconnect() ran while we were connecting; it already cleaned up.
                    throw LGTVError.connectionFailed("Connection cancelled")
                }

                if isCurrentConnectionAttempt(attemptID) {
                    tearDownSocket(reason: error)
                }

                // Trying the next endpoint after a pairing failure would put a second prompt on the TV.
                if let lgError = error as? LGTVError, lgError == .pairingRejected || lgError == .pairingTimeout {
                    publishConnectionState(.disconnected)
                    throw lgError
                }
            }
        }

        publishConnectionState(.disconnected)
        throw LGTVError.webosError("Failed to connect to TV: \(lastError?.localizedDescription ?? "Unknown error")")
    }

    private func connectWithProtocol(ipAddress: String, endpoint: WebOSConnectionEndpoint, attemptID: UInt64) async throws {
        guard let wsURL = endpoint.url(for: ipAddress) else {
            throw LGTVError.webosError("Invalid WebSocket URL")
        }

        let session = endpoint.usesSSL ? sslURLSession : urlSession
        let socket = session.webSocketTask(with: wsURL)
        usesSSL = endpoint.usesSSL
        webSocketTask = socket
        socket.resume()

        Task { [attemptID] in
            await receiveMessages(from: socket, attemptID: attemptID)
        }

        publishConnectionState(.registering, attemptID: attemptID)
        try await performHandshake(attemptID: attemptID)
    }

    func disconnect() {
        cancelGeneration &+= 1
        let attemptID = beginConnectionAttempt()
        guard _connectionState != .disconnected else {
            return
        }

        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        tearDownSocket(reason: LGTVError.webosError("Connection closed"))
        publishConnectionState(.disconnected, attemptID: attemptID)
        log("info", "Disconnected", [:])
    }

    /// Drops the socket and fails everything waiting on it. Does not publish a state.
    private func tearDownSocket(reason: Error) {
        keepAliveTask?.cancel()
        keepAliveTask = nil
        bootstrapTask?.cancel()
        bootstrapTask = nil
        webSocketTask?.cancel()
        webSocketTask = nil
        handshakeCompleted = false
        failHandshake(reason)

        let requestsToFail = pendingRequests
        pendingRequests.removeAll()
        for (_, pending) in requestsToFail {
            pending.timeoutTask.cancel()
            pending.continuation.resume(throwing: reason)
        }
    }

    private func handleConnectionFailure(_ error: Error, attemptID: UInt64? = nil) {
        guard isCurrentConnectionAttempt(attemptID) else {
            logger.debug("Ignoring stale WebOS connection failure")
            return
        }

        // The first failure is the cause; what follows (the receive loop noticing the socket
        // it was reading from is gone) would only replace the reason with a less useful one.
        guard !_connectionState.hasError else { return }

        log("warning", "Connection lost", ["error": error.localizedDescription, "state": _connectionState.description])
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        tearDownSocket(reason: error)
        publishConnectionState(.error(error), attemptID: attemptID)
    }

    // MARK: - Requests

    func sendCommand(_ command: WebOSCommand) async throws {
        guard _connectionState == .connected, handshakeCompleted else {
            throw LGTVError.webosError("Not connected to TV")
        }

        if let testSendCommandHandler {
            do {
                try await testSendCommandHandler(command)
                return
            } catch {
                let sendError = LGTVError.webosError("Failed to send command: \(error.localizedDescription)")
                handleConnectionFailure(sendError)
                throw sendError
            }
        }

        let descriptor = Self.descriptor(for: command)
        do {
            _ = try await perform(type: descriptor.type, uri: descriptor.uri, payload: descriptor.payload)
        } catch {
            // Endpoint names differ between firmware generations; try the other known name.
            if case LGTVError.commandFailed = error, let legacyURI = Self.legacyURI(for: command) {
                log("info", "Endpoint rejected; retrying its older name", ["uri": descriptor.uri, "legacy": legacyURI, "error": error.localizedDescription])
                _ = try await perform(type: "request", uri: legacyURI, payload: nil)
                return
            }
            // A TV that is switching off often closes the socket instead of replying.
            if case .powerOff = command, Self.isSilence(error) {
                log("info", "Power off sent; TV closed without replying", ["error": error.localizedDescription])
                return
            }
            if let lgError = error as? LGTVError {
                throw lgError
            }
            throw LGTVError.webosError("Failed to send command: \(error.localizedDescription)")
        }
    }

    func request(uri: String, payload: [String: Any]?) async throws -> SSAPReply {
        try await perform(type: "request", uri: uri, payload: payload)
    }

    func getPowerStatus() async throws -> TVPowerStatus {
        guard _connectionState == .connected, handshakeCompleted else {
            throw LGTVError.webosError("Not connected to TV")
        }

        if let testSendCommandHandler {
            do {
                try await testSendCommandHandler(.getPowerState)
                return TVPowerStatus()
            } catch {
                handleConnectionFailure(error)
                throw error
            }
        }

        let descriptor = Self.descriptor(for: .getPowerState)
        let reply = try await perform(type: descriptor.type, uri: descriptor.uri, payload: descriptor.payload)
        return TVPowerStatus(payload: reply.payload)
    }

    private static func legacyURI(for command: WebOSCommand) -> String? {
        switch command {
        case .mute: return "ssap://audio/mute"
        case .unmute: return "ssap://audio/unmute"
        case .getInputList: return "ssap://tv/getInputList"
        default: return nil
        }
    }

    private static func isSilence(_ error: Error) -> Bool {
        guard let lgError = error as? LGTVError else { return true }
        switch lgError {
        case .requestTimedOut, .webosError, .connectionFailed, .networkError: return true
        default: return false
        }
    }

    /// Sends one frame and suspends until the matching reply, an error frame, a timeout or a
    /// connection failure. Exactly one of those resumes the caller.
    private func perform(type: String, uri: String, payload: [String: Any]?) async throws -> SSAPReply {
        guard _connectionState == .connected, handshakeCompleted else {
            throw LGTVError.webosError("Not connected to TV")
        }

        guard let webSocketTask else {
            let error = LGTVError.webosError("WebSocket connection is unavailable")
            handleConnectionFailure(error)
            throw error
        }

        let requestID = "req_\(messageCounter)"
        messageCounter += 1
        // A send that fails after a reconnect belongs to the old socket and must not take the
        // new one down with it.
        let attemptID = connectionAttemptID

        var message: [String: Any] = ["id": requestID, "type": type, "uri": uri]
        if let payload {
            message["payload"] = payload
        }

        guard JSONSerialization.isValidJSONObject(message),
              let data = try? JSONSerialization.data(withJSONObject: message),
              let string = String(data: data, encoding: .utf8) else {
            throw LGTVError.commandFailed("Request for \(uri) could not be encoded")
        }

        logger.debug("Sending \(type, privacy: .public) \(uri, privacy: .public)")
        let replyTimeout = timeouts.reply

        return try await withCheckedThrowingContinuation { continuation in
            let timeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: replyTimeout)
                guard !Task.isCancelled else { return }
                self?.failPendingRequest(requestID, with: LGTVError.requestTimedOut(uri))
            }
            pendingRequests[requestID] = PendingRequest(uri: uri, continuation: continuation, timeoutTask: timeoutTask)

            webSocketTask.send(.string(string)) { [weak self] error in
                guard let error else { return }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.failPendingRequest(requestID, with: error)
                    self.handleConnectionFailure(error, attemptID: attemptID)
                }
            }
        }
    }

    private func failPendingRequest(_ requestID: String, with error: Error) {
        guard let pending = pendingRequests.removeValue(forKey: requestID) else { return }
        pending.timeoutTask.cancel()
        if case LGTVError.requestTimedOut = error {
            log("warning", "Request timed out", ["uri": pending.uri])
        }
        pending.continuation.resume(throwing: error)
    }

    // MARK: - Callback Registration

    func setCapabilityCallback(_ callback: @escaping @Sendable (TVCapabilities) -> Void) {
        self.capabilityCallback = callback
    }

    func setInputChangeCallback(_ callback: @escaping @Sendable (TVInputType) -> Void) {
        self.inputChangeCallback = callback
    }

    func setForegroundChangeCallback(_ callback: @escaping @Sendable (TVForeground) -> Void) {
        self.foregroundChangeCallback = callback
    }

    func setVolumeChangeCallback(_ callback: @escaping @Sendable (Int, Bool) -> Void) {
        self.volumeChangeCallback = callback
    }

    func setInputListCallback(_ callback: @escaping @Sendable ([String: String]) -> Void) {
        self.inputListCallback = callback
    }

    func setSoundOutputChangeCallback(_ callback: @escaping @Sendable (TVSoundOutput) -> Void) {
        self.soundOutputChangeCallback = callback
    }

    func setDiagnosticPayloadCallback(_ callback: @escaping (String, String) -> Void) {
        self.diagnosticPayloadCallback = callback
    }

    func setLogCallback(_ callback: @escaping (String, String, [String: String]) -> Void) {
        self.logCallback = callback
    }

    // MARK: - State

    @discardableResult
    private func beginConnectionAttempt() -> UInt64 {
        connectionAttemptID &+= 1
        return connectionAttemptID
    }

    private func isCurrentConnectionAttempt(_ attemptID: UInt64?) -> Bool {
        guard let attemptID else { return true }
        return attemptID == connectionAttemptID
    }

    private func publishConnectionState(_ state: ConnectionState, attemptID: UInt64? = nil) {
        guard isCurrentConnectionAttempt(attemptID) else {
            logger.debug("Ignoring stale WebOS state change")
            return
        }

        _connectionState = state
        stateChangeCallback?(state)
        testStateChangeObserver?(state)
    }

    private func log(_ level: String, _ message: String, _ metadata: [String: String]) {
        switch level {
        case "error": logger.error("\(message, privacy: .public) \(metadata, privacy: .public)")
        case "warning": logger.warning("\(message, privacy: .public) \(metadata, privacy: .public)")
        default: logger.info("\(message, privacy: .public) \(metadata, privacy: .public)")
        }
        logCallback?(level, message, metadata)
    }

    // MARK: - Handshake

    private func performHandshake(attemptID: UInt64) async throws {
        guard isCurrentConnectionAttempt(attemptID) else {
            throw LGTVError.webosError("Connection attempt superseded")
        }

        var existingClientKey: String?
        if let ipAddress = configuration?.ipAddress {
            existingClientKey = try? keychainManager.loadClientKey(for: ipAddress)
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

        if let clientKey = existingClientKey {
            payload["client-key"] = clientKey
        }

        let handshakeMessage: [String: Any] = [
            "id": "register_\(messageCounter)",
            "type": "register",
            "payload": payload
        ]
        messageCounter += 1

        let data = try JSONSerialization.data(withJSONObject: handshakeMessage)
        guard let string = String(data: data, encoding: .utf8) else {
            throw LGTVError.webosError("Registration message could not be encoded")
        }

        log("info", "Registering", ["hasClientKey": "\(existingClientKey != nil)"])

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.handshakeContinuation = continuation
            self.armHandshakeTimeout(
                after: timeouts.handshake,
                error: LGTVError.connectionFailed("The TV did not answer the registration request"),
                attemptID: attemptID
            )

            guard let webSocketTask else {
                self.failHandshake(LGTVError.webosError("WebSocket connection is unavailable"), attemptID: attemptID)
                return
            }

            webSocketTask.send(.string(string)) { [weak self] error in
                guard let self, let error else { return }
                Task { @MainActor in
                    self.failHandshake(error, attemptID: attemptID)
                }
            }
        }
    }

    private func armHandshakeTimeout(after duration: Duration, error: LGTVError, attemptID: UInt64) {
        handshakeTimeoutTask?.cancel()
        handshakeTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.failHandshake(error, attemptID: attemptID)
        }
    }

    private func failHandshake(_ error: Error, attemptID: UInt64? = nil) {
        guard isCurrentConnectionAttempt(attemptID) else { return }
        guard let handshakeContinuation else { return }
        handshakeTimeoutTask?.cancel()
        handshakeTimeoutTask = nil
        self.handshakeContinuation = nil
        handshakeContinuation.resume(throwing: error)
    }

    /// Replies to the registration message other than `registered`.
    private func handleRegistrationReply(type: String, messageDict: [String: Any], attemptID: UInt64?) {
        guard handshakeContinuation != nil, isCurrentConnectionAttempt(attemptID) else { return }
        let payload = messageDict["payload"] as? [String: Any] ?? [:]

        if type == "error" {
            let text = (messageDict["error"] as? String) ?? (payload["errorText"] as? String) ?? "Registration failed"
            log("warning", "Registration refused", ["error": text])
            let lowered = text.lowercased()
            if lowered.contains("403") || lowered.contains("reject") || lowered.contains("denied") || lowered.contains("cancel") {
                failHandshake(LGTVError.pairingRejected, attemptID: attemptID)
            } else if lowered.contains("timeout") || lowered.contains("timed out") {
                failHandshake(LGTVError.pairingTimeout, attemptID: attemptID)
            } else {
                failHandshake(LGTVError.connectionFailed(text), attemptID: attemptID)
            }
            return
        }

        if (payload["pairingType"] as? String)?.uppercased() == "PROMPT", let attemptID {
            log("info", "TV is showing the pairing prompt", [:])
            publishConnectionState(.awaitingPairing, attemptID: attemptID)
            armHandshakeTimeout(after: timeouts.pairingPrompt, error: LGTVError.pairingTimeout, attemptID: attemptID)
        }
    }

    private func handleRegisteredMessage(_ messageDict: [String: Any], attemptID: UInt64?) {
        guard isCurrentConnectionAttempt(attemptID) else { return }

        handshakeTimeoutTask?.cancel()
        handshakeTimeoutTask = nil
        handshakeCompleted = true
        capabilities = TVCapabilities()
        capabilities.usesSSL = usesSSL
        publishConnectionState(.connected, attemptID: attemptID)

        if let handshakeContinuation {
            self.handshakeContinuation = nil
            handshakeContinuation.resume()
        }

        if let payload = messageDict["payload"] as? [String: Any],
           let clientKey = payload["client-key"] as? String,
           let ipAddress = configuration?.ipAddress {
            do {
                try keychainManager.saveClientKey(clientKey, for: ipAddress)
            } catch {
                log("error", "Failed to save client key", ["error": error.localizedDescription])
            }
        }

        // The receive loop is the caller here, and confirmed requests need it to keep reading, so
        // the session bootstrap must run on its own task.
        bootstrapTask?.cancel()
        bootstrapTask = Task { @MainActor [weak self] in
            await self?.bootstrapSession(attemptID: attemptID)
        }

        if webSocketTask != nil {
            startKeepAlive(attemptID: attemptID)
        }
    }

    private func bootstrapSession(attemptID: UInt64?) async {
        let commands: [WebOSCommand] = [
            .getForegroundAppInfo,
            .getInputList,
            .subscribeVolume,
            .subscribeSoundOutput,
            .getSoundOutput,
            .getSystemInfo
        ]

        for command in commands {
            guard !Task.isCancelled, isCurrentConnectionAttempt(attemptID), _connectionState == .connected else { return }
            do {
                try await sendCommand(command)
            } catch {
                // Older or newer firmware may lack an endpoint; the session is still usable.
                log("info", "Bootstrap request not honoured", ["command": "\(command)", "error": error.localizedDescription])
            }
        }
    }

    /// Detects a half-open socket. A WebSocket ping is avoided because not every webOS build
    /// answers pings; a cheap read every TV supports is the safer liveness probe. Only silence
    /// counts as failure, never an error reply, and only twice running: a busy TV occasionally
    /// lets one request go unanswered on a connection that is otherwise fine.
    private func startKeepAlive(attemptID: UInt64?) {
        keepAliveTask?.cancel()
        let interval = timeouts.keepAliveInterval
        keepAliveTask = Task { @MainActor [weak self] in
            var consecutiveMisses = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled, let self,
                      self.isCurrentConnectionAttempt(attemptID),
                      self._connectionState == .connected else { return }
                do {
                    _ = try await self.perform(type: "request", uri: "ssap://audio/getVolume", payload: nil)
                    consecutiveMisses = 0
                } catch LGTVError.requestTimedOut {
                    guard self.isCurrentConnectionAttempt(attemptID), self._connectionState == .connected else { return }
                    consecutiveMisses += 1
                    if consecutiveMisses < 2 { continue }
                    self.handleConnectionFailure(LGTVError.connectionFailed("The TV stopped responding"), attemptID: attemptID)
                    return
                } catch {
                    // The TV answered, with an error: it is alive.
                    consecutiveMisses = 0
                    continue
                }
            }
        }
    }

    // MARK: - Receiving

    private func receiveMessages(from socket: URLSessionWebSocketTask, attemptID: UInt64) async {
        while isCurrentConnectionAttempt(attemptID) && (_connectionState.isTransitioning || _connectionState == .connected) {
            do {
                let message = try await socket.receive()
                guard isCurrentConnectionAttempt(attemptID) else { return }

                switch message {
                case .string(let string):
                    handleMessage(string, attemptID: attemptID)
                case .data(let data):
                    if let string = String(data: data, encoding: .utf8) {
                        handleMessage(string, attemptID: attemptID)
                    }
                @unknown default:
                    logger.warning("Unknown message type received")
                }
            } catch {
                if isCurrentConnectionAttempt(attemptID) && _connectionState != .disconnected {
                    handleConnectionFailure(error, attemptID: attemptID)
                }
                return
            }
        }
    }

    private func handleMessage(_ string: String, attemptID: UInt64? = nil) {
        guard isCurrentConnectionAttempt(attemptID) else { return }

        guard let data = string.data(using: .utf8),
              let messageDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            logger.warning("Failed to decode message")
            return
        }

        let messageType = messageDict["type"] as? String ?? "unknown"
        let messageID = messageDict["id"] as? String ?? ""

        switch messageType {
        case "registered":
            handleRegisteredMessage(messageDict, attemptID: attemptID)
        case "response", "error":
            if messageID.hasPrefix("register_") {
                handleRegistrationReply(type: messageType, messageDict: messageDict, attemptID: attemptID)
                return
            }
            let payload = messageDict["payload"] as? [String: Any] ?? [:]
            resolvePendingRequest(id: messageID, type: messageType, messageDict: messageDict, payload: payload)
            if messageType == "response" {
                diagnosticPayloadCallback?("response", SSAPReply(payload: payload).jsonString)
                applyStatePayload(payload)
            }
        case "push":
            let payload = messageDict["payload"] as? [String: Any] ?? [:]
            diagnosticPayloadCallback?("push", SSAPReply(payload: payload).jsonString)
            applyStatePayload(payload)
        default:
            logger.debug("Unhandled message type: \(messageType, privacy: .public)")
        }
    }

    private func resolvePendingRequest(id: String, type: String, messageDict: [String: Any], payload: [String: Any]) {
        guard let pending = pendingRequests.removeValue(forKey: id) else { return }
        pending.timeoutTask.cancel()

        if type == "error" {
            let text = (messageDict["error"] as? String) ?? (payload["errorText"] as? String) ?? "Request failed"
            log("warning", "TV rejected request", ["uri": pending.uri, "error": text])
            pending.continuation.resume(throwing: LGTVError.commandFailed("\(text) (\(pending.uri))"))
            return
        }

        if let returnValue = payload["returnValue"] as? Bool, returnValue == false {
            let errorText = payload["errorText"] as? String
            let errorCode = (payload["errorCode"] as? String) ?? (payload["errorCode"] as? Int).map(String.init)
            let detail = [errorText, errorCode].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
            log("warning", "TV rejected request", ["uri": pending.uri, "error": detail])
            pending.continuation.resume(throwing: LGTVError.commandFailed(detail.isEmpty ? "WebOS request failed (\(pending.uri))" : "\(detail) (\(pending.uri))"))
            return
        }

        pending.continuation.resume(returning: SSAPReply(payload: payload))
    }

    /// Updates observable TV state from any reply or subscription update that carries it.
    private func applyStatePayload(_ payload: [String: Any]) {
        if let volume = payload["volume"] as? Int {
            let isMuted = payload["muted"] as? Bool ?? payload["mute"] as? Bool ?? false
            volumeChangeCallback?(volume, isMuted)
        } else if let volumeStatus = payload["volumeStatus"] as? [String: Any],
                  let volume = volumeStatus["volume"] as? Int {
            let isMuted = volumeStatus["muteStatus"] as? Bool ?? volumeStatus["muted"] as? Bool ?? false
            volumeChangeCallback?(volume, isMuted)
        }

        if let appId = extractAppId(from: payload), let foreground = TVForeground.from(appId: appId) {
            foregroundChangeCallback?(foreground)
            if let input = foreground.input {
                inputChangeCallback?(input)
            }
        }

        if let inputSource = extractInputSource(from: payload), let inputType = mapInputSourceToType(inputSource) {
            foregroundChangeCallback?(.input(inputType))
            inputChangeCallback?(inputType)
        }

        if let devices = payload["devices"] as? [[String: Any]] {
            var inputIcons: [String: String] = [:]
            var inputs: [TVInputInfo] = []
            for device in devices {
                guard let id = device["id"] as? String else { continue }
                let icon = device["icon"] as? String ?? ""
                inputIcons[id] = icon
                inputs.append(TVInputInfo(
                    id: id,
                    label: device["label"] as? String ?? id,
                    icon: icon,
                    isConnected: device["connected"] as? Bool ?? false
                ))
            }
            if !inputs.isEmpty {
                capabilities.inputs = inputs
                capabilities.inputIcons = inputIcons
                capabilityCallback?(capabilities)
                inputListCallback?(inputIcons)
            }
        }

        if let soundOutputStr = extractSoundOutput(from: payload) {
            soundOutputChangeCallback?(TVSoundOutput.fromAPIValue(soundOutputStr))
        }

        // ssap://system/getSystemInfo
        if let displayModel = payload["modelName"] as? String {
            capabilities.displayModel = displayModel
            capabilityCallback?(capabilities)
        }
    }

    private func extractAppId(from payload: [String: Any]) -> String? {
        if let appId = payload["appId"] as? String {
            return appId
        }

        if let foregroundInfo = payload["foregroundAppInfo"] as? [String: Any],
           let appId = foregroundInfo["appId"] as? String {
            return appId
        }

        if let foregroundInfo = payload["foregroundAppInfo"] as? [[String: Any]],
           let appId = foregroundInfo.first?["appId"] as? String {
            return appId
        }

        return nil
    }

    private func extractInputSource(from payload: [String: Any]) -> String? {
        if let inputSource = payload["inputSource"] as? String {
            return inputSource
        }

        if let inputId = payload["inputId"] as? String {
            return inputId
        }

        if let input = payload["input"] as? [String: Any] {
            if let inputSource = input["inputSource"] as? String {
                return inputSource
            }
            if let inputId = input["inputId"] as? String {
                return inputId
            }
        }

        return nil
    }

    private func extractSoundOutput(from payload: [String: Any]) -> String? {
        if let soundOutput = payload["soundOutput"] as? String {
            return soundOutput
        }

        if let output = payload["output"] as? String {
            return output
        }

        if let soundOutput = payload["soundOutput"] as? [String: Any] {
            if let nestedOutput = soundOutput["soundOutput"] as? String {
                return nestedOutput
            }
            if let nestedOutput = soundOutput["output"] as? String {
                return nestedOutput
            }
        }

        if let volumeStatus = payload["volumeStatus"] as? [String: Any],
           let soundOutput = volumeStatus["soundOutput"] as? String {
            return soundOutput
        }

        if let status = payload["status"] as? [String: Any],
           let soundOutput = status["soundOutput"] as? String {
            return soundOutput
        }

        return nil
    }

    /// Returns nil for sources this app does not model, rather than guessing an input.
    private func mapInputSourceToType(_ inputSource: String) -> TVInputType? {
        switch inputSource.lowercased() {
        case "hdmi_1", "hdmi1": return .hdmi1
        case "hdmi_2", "hdmi2": return .hdmi2
        case "hdmi_3", "hdmi3": return .hdmi3
        case "hdmi_4", "hdmi4": return .hdmi4
        case "dp_1", "displayport1": return .displayPort1
        case "dp_2", "displayport2": return .displayPort2
        case "usb_c_1", "usbc_1", "usbc1": return .usbC1
        case "usb_c_2", "usbc_2", "usbc2": return .usbC2
        default: return nil
        }
    }

    // MARK: - Command Encoding

    struct CommandDescriptor {
        let type: String
        let uri: String
        let payload: [String: Any]?
    }

    static func descriptor(for command: WebOSCommand) -> CommandDescriptor {
        func request(_ uri: String, _ payload: [String: Any]? = nil) -> CommandDescriptor {
            CommandDescriptor(type: "request", uri: uri, payload: payload)
        }
        func subscribe(_ uri: String) -> CommandDescriptor {
            CommandDescriptor(type: "subscribe", uri: uri, payload: nil)
        }

        switch command {
        case .getForegroundAppInfo:
            return subscribe("ssap://com.webos.applicationManager/getForegroundAppInfo")
        case .getCurrentForegroundAppInfo:
            return request("ssap://com.webos.applicationManager/getForegroundAppInfo")
        case .getInputList:
            return request("ssap://tv/getExternalInputList")
        case .powerOn:
            return request("ssap://system/turnOn")
        case .powerOff:
            return request("ssap://system/turnOff")
        case .volumeUp:
            return request("ssap://audio/volumeUp")
        case .volumeDown:
            return request("ssap://audio/volumeDown")
        case .setVolume(let level):
            return request("ssap://audio/setVolume", ["volume": level])
        case .getVolume:
            return request("ssap://audio/getVolume")
        case .subscribeVolume:
            return subscribe("ssap://audio/getVolume")
        case .getPowerState:
            return request("ssap://com.webos.service.tvpower/power/getPowerState")
        case .mute:
            return request("ssap://audio/setMute", ["mute": true])
        case .unmute:
            return request("ssap://audio/setMute", ["mute": false])
        case .setInput(let inputId):
            return request("ssap://tv/switchInput", ["inputId": inputId])
        case .screenOn:
            return request("ssap://com.webos.service.tvpower/power/turnOnScreen", ["standbyMode": "active"])
        case .screenOff:
            return request("ssap://com.webos.service.tvpower/power/turnOffScreen", ["standbyMode": "active"])
        case .setDeviceInfo(let inputId, let icon, let label):
            return request("ssap://com.webos.service.eim/setDeviceInfo", ["id": inputId, "icon": "\(icon).png", "label": label])
        case .getSoundOutput:
            return request("ssap://com.webos.service.apiadapter/audio/getSoundOutput")
        case .subscribeSoundOutput:
            return subscribe("ssap://com.webos.service.apiadapter/audio/getSoundOutput")
        case .setSoundOutput(let output):
            return request("ssap://com.webos.service.apiadapter/audio/changeSoundOutput", ["output": output])
        case .getSystemInfo:
            return request("ssap://system/getSystemInfo")
        }
    }
}
