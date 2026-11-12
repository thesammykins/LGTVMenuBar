import Foundation
@testable import LGTVMenuBar
import Network

/// An in-process SSAP server on loopback that behaves like a webOS TV for the cases the client
/// has to survive: silence, slow pairing, refusal, rejected commands, missing replies and drops.
final class FakeTV: @unchecked Sendable {
    enum Registration: Sendable {
        case accept
        case promptThenAccept(after: TimeInterval)
        case promptOnly
        case reject
        case silent
    }

    struct ReceivedRequest {
        let type: String
        let uri: String
        let payload: [String: Any]
    }

    private let queue = DispatchQueue(label: "FakeTV")
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private var subscriptionIDs: [String: String] = [:]

    private var _registration: Registration = .accept
    private var _replies: [String: [String: Any]] = [:]
    private var _silentURIs: Set<String> = []
    private var _received: [ReceivedRequest] = []
    private var _registerCount = 0
    private var _port: UInt16 = 0
    private var startResolved = false

    var registration: Registration {
        get { queue.sync { _registration } }
        set { queue.sync { _registration = newValue } }
    }

    /// Reply payloads by URI. A URI without an entry answers `{"returnValue": true}`.
    func setReply(_ payload: [String: Any], for uri: String) {
        queue.sync { _replies[uri] = payload }
    }

    /// Requests for these URIs are received and never answered.
    func setSilent(_ uri: String) {
        queue.sync { _ = _silentURIs.insert(uri) }
    }

    var received: [ReceivedRequest] { queue.sync { _received } }
    var registerCount: Int { queue.sync { _registerCount } }
    var port: Int { Int(queue.sync { _port }) }

    func requestCount(for uri: String) -> Int {
        received.filter { $0.uri == uri }.count
    }

    func start() async throws {
        let webSocketOptions = NWProtocolWebSocket.Options()
        webSocketOptions.autoReplyPing = true
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        parameters.defaultProtocolStack.applicationProtocols.insert(webSocketOptions, at: 0)

        let listener = try NWListener(using: parameters)
        self.listener = listener

        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            listener.stateUpdateHandler = { [weak self] state in
                guard let self, !self.startResolved else { return }
                switch state {
                case .ready:
                    self.startResolved = true
                    self._port = listener.port?.rawValue ?? 0
                    continuation.resume()
                case .failed(let error):
                    self.startResolved = true
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    func stop() {
        queue.sync {
            listener?.cancel()
            listener = nil
            connections.forEach { $0.cancel() }
            connections.removeAll()
        }
    }

    /// Closes every client socket without a WebSocket close handshake, like a TV losing power.
    func dropConnections() {
        queue.sync {
            connections.forEach { $0.cancel() }
            connections.removeAll()
        }
    }

    /// Sends a subscription update for a URI the client subscribed to.
    func push(_ payload: [String: Any], for uri: String) {
        queue.sync {
            guard let id = subscriptionIDs[uri] else { return }
            broadcast(["type": "response", "id": id, "payload": payload])
        }
    }

    // MARK: - Private (always on `queue`)

    private func accept(_ connection: NWConnection) {
        connections.append(connection)
        connection.start(queue: queue)
        receive(on: connection)
    }

    private func receive(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self, error == nil, let data, !data.isEmpty else { return }
            if let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                self.handle(message, on: connection)
            }
            self.receive(on: connection)
        }
    }

    private func handle(_ message: [String: Any], on connection: NWConnection) {
        let type = message["type"] as? String ?? ""
        let id = message["id"] as? String ?? ""

        if type == "register" {
            _registerCount += 1
            switch _registration {
            case .accept:
                send(["type": "registered", "id": id, "payload": ["client-key": "fake-client-key"]], on: connection)
            case .promptThenAccept(let delay):
                send(["type": "response", "id": id, "payload": ["pairingType": "PROMPT", "returnValue": true]], on: connection)
                queue.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.send(["type": "registered", "id": id, "payload": ["client-key": "fake-client-key"]], on: connection)
                }
            case .promptOnly:
                send(["type": "response", "id": id, "payload": ["pairingType": "PROMPT", "returnValue": true]], on: connection)
            case .reject:
                send(["type": "response", "id": id, "payload": ["pairingType": "PROMPT", "returnValue": true]], on: connection)
                send(["type": "error", "id": id, "error": "403 User rejected pairing", "payload": [:] as [String: Any]], on: connection)
            case .silent:
                break
            }
            return
        }

        let uri = message["uri"] as? String ?? ""
        _received.append(ReceivedRequest(type: type, uri: uri, payload: message["payload"] as? [String: Any] ?? [:]))

        if type == "subscribe" {
            subscriptionIDs[uri] = id
        }
        guard !_silentURIs.contains(uri) else { return }

        var payload = _replies[uri] ?? [:]
        if payload["returnValue"] == nil {
            payload["returnValue"] = true
        }
        send(["type": "response", "id": id, "payload": payload], on: connection)
    }

    private func broadcast(_ message: [String: Any]) {
        connections.forEach { send(message, on: $0) }
    }

    private func send(_ message: [String: Any], on connection: NWConnection) {
        guard let data = try? JSONSerialization.data(withJSONObject: message) else { return }
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "text", metadata: [metadata])
        connection.send(content: data, contentContext: context, isComplete: true, completion: .idempotent)
    }
}

/// Reachability stub for controller tests.
struct StubReachabilityProbe: TVReachabilityProbing {
    let reachable: Bool
    func isReachable(host: String, timeout: Duration) async -> Bool { reachable }
}

/// Reachability stub that answers from a script, then keeps giving its last answer.
final class ScriptedReachabilityProbe: TVReachabilityProbing, @unchecked Sendable {
    private let lock = NSLock()
    private var answers: [Bool]
    private var _callCount = 0

    init(answers: [Bool]) {
        self.answers = answers
    }

    var callCount: Int { lock.withLock { _callCount } }

    func isReachable(host: String, timeout: Duration) async -> Bool {
        lock.withLock {
            _callCount += 1
            return answers.count > 1 ? answers.removeFirst() : answers.first ?? false
        }
    }
}
