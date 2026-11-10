import Foundation
import Network
@testable import LGTVMenuBar

/// Scripted root shell: maps commands to outputs and records what was asked.
final class FakeRootShell: RootShellRunning, @unchecked Sendable {
    struct Call {
        let command: String
        let endpoint: RootShellEndpoint
        let credential: RootShellCredential
        let trustedHostKeyFingerprint: String?
    }

    private let lock = NSLock()
    private var _calls: [Call] = []
    private var _handler: (String) throws -> RootShellOutput = { _ in RootShellOutput(output: "", exitStatus: 0) }

    var calls: [Call] { lock.lock(); defer { lock.unlock() }; return _calls }

    func setHandler(_ handler: @escaping (String) throws -> RootShellOutput) {
        lock.lock(); _handler = handler; lock.unlock()
    }

    func run(_ command: String, endpoint: RootShellEndpoint, credential: RootShellCredential, trustedHostKeyFingerprint: String?, timeout: Duration) async throws -> RootShellOutput {
        let handler = record(Call(command: command, endpoint: endpoint, credential: credential, trustedHostKeyFingerprint: trustedHostKeyFingerprint))
        return try handler(command)
    }

    private func record(_ call: Call) -> (String) throws -> RootShellOutput {
        lock.lock()
        defer { lock.unlock() }
        _calls.append(call)
        return _handler
    }
}

/// A loopback TCP server that talks just enough Telnet to look like a TV's busybox shell.
final class FakeTelnetServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "FakeTelnetServer")
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private var buffers: [ObjectIdentifier: String] = [:]
    private var stages: [ObjectIdentifier: Int] = [:]
    private var _port: UInt16 = 0
    private var startResolved = false

    /// When set, the server asks for a login and this password before giving a prompt.
    let requiredPassword: String?
    /// Output the fake shell prints for any command.
    let commandOutput: String
    let exitStatus: Int

    init(requiredPassword: String? = nil, commandOutput: String = "0", exitStatus: Int = 0) {
        self.requiredPassword = requiredPassword
        self.commandOutput = commandOutput
        self.exitStatus = exitStatus
    }

    var port: Int { Int(queue.sync { _port }) }

    func start() async throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }

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
            connections.forEach { $0.cancel() }
            connections.removeAll()
        }
    }

    private func accept(_ connection: NWConnection) {
        connections.append(connection)
        let id = ObjectIdentifier(connection)
        buffers[id] = ""
        stages[id] = requiredPassword == nil ? 2 : 0
        connection.start(queue: queue)

        // IAC WILL ECHO, IAC DO NAWS, then a banner.
        var greeting = Data([255, 251, 1, 255, 253, 31])
        greeting.append(Data((requiredPassword == nil ? "webOS TV\r\n# " : "webOS TV\r\nlogin: ").utf8))
        connection.send(content: greeting, completion: .contentProcessed { _ in })
        receive(on: connection)
    }

    private func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, _, error in
            guard let self, error == nil, let data, !data.isEmpty else { return }
            // Drop client negotiation replies (3-byte IAC sequences).
            var bytes = [UInt8](data)
            while let index = bytes.firstIndex(of: 255), index + 2 < bytes.count {
                bytes.removeSubrange(index...index + 2)
            }
            let id = ObjectIdentifier(connection)
            self.buffers[id, default: ""] += String(decoding: bytes, as: UTF8.self)
            self.processLines(for: connection)
            self.receive(on: connection)
        }
    }

    private func processLines(for connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        while let newline = buffers[id]?.firstIndex(of: "\n") {
            let line = String(buffers[id]![..<newline]).trimmingCharacters(in: .whitespacesAndNewlines)
            buffers[id]!.removeSubrange(...newline)

            switch stages[id] ?? 2 {
            case 0:
                stages[id] = 1
                send("Password: ", on: connection)
            case 1:
                if line == requiredPassword {
                    stages[id] = 2
                    send("\r\n# ", on: connection)
                } else {
                    send("\r\nLogin incorrect\r\nlogin: ", on: connection)
                    stages[id] = 0
                }
            default:
                guard let range = line.range(of: #"__LGTV_BEGIN_([A-F0-9]+)__"#, options: .regularExpression) else {
                    send("# ", on: connection)
                    continue
                }
                let nonce = line[range].dropFirst("__LGTV_BEGIN_".count).dropLast(2)
                // A real shell echoes the typed line before running it.
                send("\(line)\r\n__LGTV_BEGIN_\(nonce)__\r\n\(commandOutput)\r\n__LGTV_DONE_\(nonce)_\(exitStatus)__\r\n# ", on: connection)
            }
        }
    }

    private func send(_ text: String, on connection: NWConnection) {
        connection.send(content: Data(text.utf8), completion: .contentProcessed { _ in })
    }
}
