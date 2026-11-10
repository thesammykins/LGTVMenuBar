import Foundation
import Network

/// Answers "is the TV's control port accepting connections right now" without touching SSAP.
public protocol TVReachabilityProbing: Sendable {
    func isReachable(host: String, timeout: Duration) async -> Bool
}

/// Resumes a continuation exactly once when two callbacks race.
final class ResumeOnce<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Never>?

    init(_ continuation: CheckedContinuation<Value, Never>) {
        self.continuation = continuation
    }

    func resume(_ value: Value) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
    }
}

/// TCP probe of the SSAP ports. A TV in standby closes them, so an accepted connection means the
/// TV is on (or at least awake enough to pair with).
public struct TCPReachabilityProbe: TVReachabilityProbing {
    private let ports: [UInt16]

    public init(ports: [UInt16] = [3001, 3000]) {
        self.ports = ports
    }

    public func isReachable(host: String, timeout: Duration) async -> Bool {
        // Ports are tried together so an unreachable TV costs one timeout, not one per port.
        await withTaskGroup(of: Bool.self) { group in
            for port in ports {
                group.addTask { await Self.canConnect(host: host, port: port, timeout: timeout) }
            }
            for await reachable in group where reachable {
                group.cancelAll()
                return true
            }
            return false
        }
    }

    static func canConnect(host: String, port: UInt16, timeout: Duration) async -> Bool {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return false }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        let queue = DispatchQueue(label: "com.lgtvmenubar.reachability")

        let result = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let once = ResumeOnce(continuation)
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    once.resume(true)
                case .failed, .cancelled:
                    once.resume(false)
                case .waiting:
                    // No route or refused; do not wait for the network to change.
                    once.resume(false)
                default:
                    break
                }
            }
            connection.start(queue: queue)
            let components = timeout.components
            let seconds = Double(components.seconds) + Double(components.attoseconds) / 1e18
            queue.asyncAfter(deadline: .now() + seconds) {
                once.resume(false)
            }
        }

        connection.cancel()
        return result
    }
}
