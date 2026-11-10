import Foundation
import Network

/// Root shell over Telnet, for TVs where only Homebrew Channel's Telnet service is enabled.
///
/// Telnet is unencrypted and, as shipped by Homebrew Channel, unauthenticated. The app offers it
/// because some rooted TVs expose nothing else, and says so in Settings.
public struct TelnetRootShell: RootShellRunning {
    public init() {}

    public func run(
        _ command: String,
        endpoint: RootShellEndpoint,
        credential: RootShellCredential,
        trustedHostKeyFingerprint: String?,
        timeout: Duration
    ) async throws -> RootShellOutput {
        let nonce = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let session = TelnetSession(endpoint: endpoint, credential: credential)
        defer { session.close() }

        return try await withDeadline(timeout, timeoutError: RootShellError.timedOut) {
            try await session.open()
            await session.waitForPrompt(upTo: .seconds(2))
            session.send(RootShellFraming.wrap(command, nonce: nonce) + "\n")

            while true {
                try Task.checkCancellation()
                if let failure = session.failure {
                    throw failure
                }
                if let result = RootShellFraming.extract(from: session.text, nonce: nonce) {
                    return RootShellOutput(output: result.output, exitStatus: result.status)
                }
                try await Task.sleep(for: .milliseconds(40))
            }
        }
    }
}

/// One Telnet connection. Network callbacks arrive on `queue`; shared state is behind `lock`.
private final class TelnetSession: @unchecked Sendable {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "com.lgtvmenubar.telnet")
    private let lock = NSLock()
    private let endpoint: RootShellEndpoint
    private let credential: RootShellCredential

    private var _text = ""
    private var _failure: RootShellError?
    private var sentLogin = false
    private var sentPassword = false
    private var pendingCommandBytes: [UInt8] = []

    init(endpoint: RootShellEndpoint, credential: RootShellCredential) {
        self.endpoint = endpoint
        self.credential = credential
        let port = NWEndpoint.Port(rawValue: UInt16(clamping: endpoint.port)) ?? 23
        self.connection = NWConnection(host: NWEndpoint.Host(endpoint.host), port: port, using: .tcp)
    }

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return _text
    }

    var failure: RootShellError? {
        lock.lock()
        defer { lock.unlock() }
        return _failure
    }

    func open() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let once = ThrowingResumeOnce(continuation)
            connection.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    once.resume(.success(()))
                    self?.receive()
                case .failed(let error):
                    let failure = RootShellError.connectionFailed(error.localizedDescription)
                    self?.record(failure)
                    once.resume(.failure(failure))
                case .waiting(let error):
                    let failure = RootShellError.connectionFailed(error.localizedDescription)
                    self?.record(failure)
                    once.resume(.failure(failure))
                default:
                    break
                }
            }
            connection.start(queue: queue)
        }
    }

    /// Waits for something that looks like a shell prompt. Returning without one is fine: the
    /// command is framed with markers, so it does not matter what precedes it.
    func waitForPrompt(upTo limit: Duration) async {
        let deadline = ContinuousClock.now + limit
        while ContinuousClock.now < deadline {
            let current = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if current.hasSuffix("#") || current.hasSuffix("$") || current.hasSuffix(">") {
                return
            }
            try? await Task.sleep(for: .milliseconds(40))
        }
    }

    func send(_ string: String) {
        connection.send(content: Data(string.utf8), completion: .contentProcessed { [weak self] error in
            if let error {
                self?.record(.connectionFailed(error.localizedDescription))
            }
        })
    }

    func close() {
        connection.cancel()
    }

    private func record(_ failure: RootShellError) {
        lock.lock()
        if _failure == nil { _failure = failure }
        lock.unlock()
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.consume(data)
            }
            if let error {
                self.record(.connectionFailed(error.localizedDescription))
                return
            }
            if isComplete {
                self.record(.connectionFailed("The TV closed the Telnet session."))
                return
            }
            self.receive()
        }
    }

    /// Strips Telnet option negotiation, refusing every option, and answers login prompts.
    private func consume(_ data: Data) {
        let bytes = pendingCommandBytes + [UInt8](data)
        pendingCommandBytes = []
        var plain: [UInt8] = []
        var reply: [UInt8] = []
        var index = 0

        let iac: UInt8 = 255, dont: UInt8 = 254, doOption: UInt8 = 253, wont: UInt8 = 252, will: UInt8 = 251, subBegin: UInt8 = 250, subEnd: UInt8 = 240

        while index < bytes.count {
            let byte = bytes[index]
            guard byte == iac else {
                plain.append(byte)
                index += 1
                continue
            }
            guard index + 1 < bytes.count else {
                pendingCommandBytes = Array(bytes[index...])
                break
            }
            let command = bytes[index + 1]
            switch command {
            case doOption, dont, will, wont:
                guard index + 2 < bytes.count else {
                    pendingCommandBytes = Array(bytes[index...])
                    index = bytes.count
                    continue
                }
                let option = bytes[index + 2]
                if command == doOption { reply += [iac, wont, option] }
                if command == will { reply += [iac, dont, option] }
                index += 3
            case subBegin:
                if let end = (index + 2..<bytes.count).first(where: { bytes[$0] == subEnd && bytes[$0 - 1] == iac }) {
                    index = end + 1
                } else {
                    pendingCommandBytes = Array(bytes[index...])
                    index = bytes.count
                }
            case iac:
                plain.append(iac)
                index += 2
            default:
                index += 2
            }
        }

        if !reply.isEmpty {
            connection.send(content: Data(reply), completion: .contentProcessed { _ in })
        }

        let chunk = String(decoding: plain, as: UTF8.self)
        lock.lock()
        _text += chunk
        let tail = String(_text.suffix(80)).lowercased()
        lock.unlock()

        if !sentLogin, tail.contains("login:") {
            sentLogin = true
            send(endpoint.username + "\n")
        } else if !sentPassword, tail.contains("password:") {
            sentPassword = true
            if case .password(let password) = credential {
                send(password + "\n")
            } else {
                record(.authenticationFailed)
            }
        } else if tail.contains("login incorrect") {
            record(.authenticationFailed)
        }
    }
}
