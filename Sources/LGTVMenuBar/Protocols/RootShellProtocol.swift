import Foundation

/// Where a root shell lives.
public struct RootShellEndpoint: Equatable, Sendable {
    public let host: String
    public let port: Int
    public let username: String

    public init(host: String, port: Int, username: String) {
        self.host = host
        self.port = port
        self.username = username
    }
}

public enum RootShellCredential: Equatable, Sendable {
    case none
    case password(String)
    /// Raw 32-byte Ed25519 private key.
    case ed25519PrivateKey(Data)
}

public struct RootShellOutput: Equatable, Sendable {
    public let output: String
    public let exitStatus: Int?
    /// SHA-256 fingerprint of the host key the server presented (SSH only).
    public let hostKeyFingerprint: String?

    public init(output: String, exitStatus: Int?, hostKeyFingerprint: String? = nil) {
        self.output = output
        self.exitStatus = exitStatus
        self.hostKeyFingerprint = hostKeyFingerprint
    }
}

public enum RootShellError: Error, Equatable, LocalizedError, Sendable {
    case notConfigured(String)
    case connectionFailed(String)
    case authenticationFailed
    case hostKeyMismatch(expected: String, actual: String)
    case timedOut
    case malformedOutput(String)
    case commandFailed(status: Int, output: String)

    public var errorDescription: String? {
        switch self {
        case .notConfigured(let detail):
            return detail
        case .connectionFailed(let detail):
            return "Could not reach the TV's shell: \(detail)"
        case .authenticationFailed:
            return "The TV refused the login. Check the user name and the key or password."
        case .hostKeyMismatch(let expected, let actual):
            return "The device at this address is not the TV that was trusted before (expected \(expected), got \(actual)). Forget the saved host key only if you reset or re-rooted the TV."
        case .timedOut:
            return "The TV's shell did not respond in time."
        case .malformedOutput(let detail):
            return "Unexpected shell output: \(detail)"
        case .commandFailed(let status, let output):
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "The command exited with status \(status)." : "The command exited with status \(status): \(trimmed)"
        }
    }
}

/// Runs one command in a root shell and returns its combined output.
///
/// Each call opens its own connection. Shell access is used a few times per session (a probe, a
/// settings write), so a connection per command is simpler and safer than a kept-alive session
/// that has to survive TV standby.
public protocol RootShellRunning: Sendable {
    func run(
        _ command: String,
        endpoint: RootShellEndpoint,
        credential: RootShellCredential,
        trustedHostKeyFingerprint: String?,
        timeout: Duration
    ) async throws -> RootShellOutput
}

enum RootShellFraming {
    /// Wraps a command so its output and exit status can be picked out of a noisy stream
    /// (login banners, prompts, echoed input).
    static func wrap(_ command: String, nonce: String) -> String {
        "echo __LGTV_BEGIN_\(nonce)__; \(command); echo __LGTV_DONE_\(nonce)_$?__"
    }

    /// Returns nil until the completion marker has arrived.
    static func extract(from stream: String, nonce: String) -> (output: String, status: Int)? {
        // The echoed command line also contains both markers, but there the status is the
        // literal "$?" rather than digits and the begin marker is followed by ";", so only real
        // output matches these patterns.
        let escaped = NSRegularExpression.escapedPattern(for: nonce)
        guard let doneExpression = try? NSRegularExpression(pattern: "__LGTV_DONE_\(escaped)_(\\d+)__"),
              let beginExpression = try? NSRegularExpression(pattern: "__LGTV_BEGIN_\(escaped)__\\r?\\n") else {
            return nil
        }

        let text = stream as NSString
        let whole = NSRange(location: 0, length: text.length)
        guard let done = doneExpression.matches(in: stream, range: whole).last,
              let status = Int(text.substring(with: done.range(at: 1))) else {
            return nil
        }

        let head = NSRange(location: 0, length: done.range.location)
        guard let begin = beginExpression.matches(in: stream, range: head).last else {
            return nil
        }

        let bodyStart = begin.range.location + begin.range.length
        let body = text.substring(with: NSRange(location: bodyStart, length: done.range.location - bodyStart))
            .replacingOccurrences(of: "\r\n", with: "\n")
        return (body.trimmingCharacters(in: .newlines), status)
    }

    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

/// Runs an operation with a deadline that holds even if the operation ignores cancellation.
func withDeadline<T: Sendable>(
    _ timeout: Duration,
    timeoutError: Error,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
        let once = ThrowingResumeOnce(continuation)
        let work = Task {
            do {
                once.resume(.success(try await operation()))
            } catch {
                once.resume(.failure(error))
            }
        }
        Task {
            try? await Task.sleep(for: timeout)
            once.resume(.failure(timeoutError))
            work.cancel()
        }
    }
}

final class ThrowingResumeOnce<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?

    init(_ continuation: CheckedContinuation<Value, Error>) {
        self.continuation = continuation
    }

    func resume(_ result: Result<Value, Error>) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(with: result)
    }
}
