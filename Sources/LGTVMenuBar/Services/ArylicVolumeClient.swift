#if LOCAL_ARYLIC_BUILD

import Foundation
import Network

// MARK: - ArylicError

/// Errors that can occur during Arylic TCP communication.
public enum ArylicError: Error, Equatable, LocalizedError {
    case connectionFailed(String)
    case invalidResponse(String)
    case timeout
    
    public var errorDescription: String? {
        switch self {
        case .connectionFailed(let message):
            return "Connection to Arylic device failed: \(message)"
        case .invalidResponse(let message):
            return "Invalid response from Arylic device: \(message)"
        case .timeout:
            return "Arylic device communication timed out"
        }
    }
}

// MARK: - ArylicVolumeClient

/// TCP client for communicating with Arylic audio device volume control API.
///
/// Communicates via TCP sockets on port 8899 using a binary packet protocol:
/// - Header: 4 bytes (0x18, 0x96, 0x18, 0x20)
/// - Length: 4 bytes, little-endian UInt32, length of payload
/// - Checksum: 4 bytes, little-endian UInt32, sum of all payload bytes
/// - Reserved: 8 zero bytes
/// - Payload: ASCII command string
public final class ArylicVolumeClient: ArylicVolumeClientProtocol, Sendable {
    private let settings: ArylicSettings
    
    // MARK: - Initialization
    
    /// Creates a new Arylic volume client.
    ///
    /// - Parameter settings: Arylic device connection settings
    public init(settings: ArylicSettings) {
        self.settings = settings
    }
    
    // MARK: - ArylicVolumeClientProtocol
    
    public func getPlayerStatus() async throws -> (volume: Int, isMuted: Bool) {
        let volumeResponse = try await sendCommand("MCU+PAS+RAKOIT:VOL&", expectResponse: true)
        let muteResponse = try await sendCommand("MCU+PAS+RAKOIT:MUT&", expectResponse: true)
        
        let volume = try Self.parseVolumeValue(from: volumeResponse)
        let isMuted = try Self.parseMuteValue(from: muteResponse)
        
        return (volume: volume, isMuted: isMuted)
    }
    
    public func volumeUp() async throws {
        let (currentVolume, _) = try await getPlayerStatus()
        let newVolume = min(currentVolume + 1, 100)
        try await setVolume(newVolume)
    }
    
    public func volumeDown() async throws {
        let (currentVolume, _) = try await getPlayerStatus()
        let newVolume = max(currentVolume - 1, 0)
        try await setVolume(newVolume)
    }
    
    public func setVolume(_ volume: Int) async throws {
        let clampedVolume = min(max(volume, 0), 100)
        _ = try await sendCommand("MCU+PAS+RAKOIT:VOL:\(clampedVolume)&", expectResponse: false)
    }
    
    public func setMute(_ muted: Bool) async throws {
        let muteValue = muted ? "1" : "0"
        _ = try await sendCommand("MCU+PAS+RAKOIT:MUT:\(muteValue)&", expectResponse: false)
    }
    
    // MARK: - Internal Packet Building and Parsing (Testable)
    
    /// Builds a binary packet for a TCP command.
    ///
    /// - Parameter command: ASCII command string (e.g., "MCU+VOL+GET")
    /// - Returns: Binary packet data ready to send over TCP
    internal static func buildPacket(command: String) -> Data {
        let payload = Data(command.utf8)
        let length = UInt32(payload.count)
        
        // Calculate checksum: sum of all payload bytes
        let checksum: UInt32 = payload.reduce(0) { sum, byte in
            sum &+ UInt32(byte)
        }
        
        var packet = Data()
        
        // Header: 4 bytes (0x18, 0x96, 0x18, 0x20)
        packet.append(contentsOf: [0x18, 0x96, 0x18, 0x20])
        
        // Length: 4 bytes, little-endian
        withUnsafeBytes(of: length.littleEndian) { bytes in
            packet.append(contentsOf: bytes)
        }
        
        // Checksum: 4 bytes, little-endian
        withUnsafeBytes(of: checksum.littleEndian) { bytes in
            packet.append(contentsOf: bytes)
        }
        
        // Reserved: 8 zero bytes
        packet.append(contentsOf: [0, 0, 0, 0, 0, 0, 0, 0])
        
        // Payload
        packet.append(payload)
        
        return packet
    }
    
    /// Parses the payload from a binary response packet.
    ///
    /// - Parameter data: Binary response packet
    /// - Returns: ASCII payload string (e.g., "AXX+VOL+030")
    /// - Throws: ArylicError.invalidResponse if packet is malformed
    internal static func parseResponsePayload(from data: Data) throws -> String {
        // Minimum packet size: 20 bytes (header + length + checksum + reserved)
        guard data.count >= 20 else {
            throw ArylicError.invalidResponse("Response packet too short (< 20 bytes)")
        }
        
        // Verify header
        let expectedHeader: [UInt8] = [0x18, 0x96, 0x18, 0x20]
        let actualHeader = Array(data.prefix(4))
        guard actualHeader == expectedHeader else {
            throw ArylicError.invalidResponse("Invalid packet header")
        }
        
        // Extract length (bytes 4-7, little-endian)
        let lengthBytes = data[4..<8]
        let length = lengthBytes.withUnsafeBytes { bytes in
            bytes.loadUnaligned(as: UInt32.self).littleEndian
        }
        
        // Extract payload (after 20-byte header)
        guard data.count >= 20 + Int(length) else {
            throw ArylicError.invalidResponse("Response packet incomplete (expected \(20 + length) bytes, got \(data.count))")
        }
        
        let payloadData = data[20..<(20 + Int(length))]
        
        guard let payload = String(data: payloadData, encoding: .ascii) else {
            throw ArylicError.invalidResponse("Failed to decode payload as ASCII")
        }
        
        return payload
    }
    
    /// Parses volume value from passthrough response payload.
    ///
    /// BP10XX passthrough responses use format: `MCU+PAS+RAKOIT:VOL:{value}&`
    ///
    /// - Parameter response: Response payload (e.g., "MCU+PAS+RAKOIT:VOL:50&")
    /// - Returns: Volume value (0-100)
    /// - Throws: ArylicError.invalidResponse if format is invalid
    internal static func parseVolumeValue(from response: String) throws -> Int {
        let trimmed = response.hasSuffix("&") ? String(response.dropLast()) : response
        let prefix = "MCU+PAS+RAKOIT:VOL:"
        guard trimmed.hasPrefix(prefix),
              let volume = Int(trimmed.dropFirst(prefix.count)) else {
            throw ArylicError.invalidResponse("Invalid volume response format: \(response)")
        }
        return volume
    }
    
    /// Parses mute value from passthrough response payload.
    ///
    /// BP10XX passthrough responses use format: `MCU+PAS+RAKOIT:MUT:{value}&`
    ///
    /// - Parameter response: Response payload (e.g., "MCU+PAS+RAKOIT:MUT:0&")
    /// - Returns: Mute state (true if muted, false if unmuted)
    /// - Throws: ArylicError.invalidResponse if format is invalid
    internal static func parseMuteValue(from response: String) throws -> Bool {
        let trimmed = response.hasSuffix("&") ? String(response.dropLast()) : response
        let prefix = "MCU+PAS+RAKOIT:MUT:"
        guard trimmed.hasPrefix(prefix),
              let muteInt = Int(trimmed.dropFirst(prefix.count)) else {
            throw ArylicError.invalidResponse("Invalid mute response format: \(response)")
        }
        return muteInt != 0
    }
    
    // MARK: - Private TCP Communication
    
    /// Sends a TCP command and optionally waits for a response.
    ///
    /// - Parameters:
    ///   - command: ASCII command string
    ///   - expectResponse: Whether to wait for a response packet
    /// - Returns: Response payload string if expectResponse is true, empty string otherwise
    /// - Throws: ArylicError if connection fails, times out, or response is invalid
    private func sendCommand(_ command: String, expectResponse: Bool) async throws -> String {
        let connection = NWConnection(
            host: NWEndpoint.Host(settings.host),
            port: NWEndpoint.Port(integerLiteral: UInt16(settings.port)),
            using: .tcp
        )
        
        defer {
            connection.cancel()
        }
        
        // Connect with timeout
        try await withTimeout(seconds: settings.timeout) {
            try await self.connect(connection)
        }
        
        // Send packet
        let packet = Self.buildPacket(command: command)
        
        if expectResponse {
            // Standard send — connection stays alive for the subsequent receive
            try await withTimeout(seconds: settings.timeout) {
                try await self.send(data: packet, on: connection)
            }
            let responseData = try await withTimeout(seconds: settings.timeout) {
                try await self.receive(on: connection)
            }
            return try Self.parseResponsePayload(from: responseData)
        } else {
            // Fire-and-forget: use .finalMessage to flush data before connection.cancel() in defer
            try await withTimeout(seconds: settings.timeout) {
                try await self.sendFinal(data: packet, on: connection)
            }
            return ""
        }
    }
    
    /// Establishes TCP connection.
    ///
    /// - Parameter connection: NWConnection to connect
    /// - Throws: ArylicError.connectionFailed if connection fails
    private func connect(_ connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            // Use a class wrapper to make the resumed flag thread-safe
            final class ResumeState: @unchecked Sendable {
                private let lock = NSLock()
                private var _resumed = false
                
                var resumed: Bool {
                    lock.lock()
                    defer { lock.unlock() }
                    return _resumed
                }
                
                func markResumed() {
                    lock.lock()
                    defer { lock.unlock() }
                    _resumed = true
                }
            }
            
            let state = ResumeState()
            
            connection.stateUpdateHandler = { connectionState in
                guard !state.resumed else { return }
                
                switch connectionState {
                case .ready:
                    state.markResumed()
                    continuation.resume()
                case .failed(let error):
                    state.markResumed()
                    continuation.resume(throwing: ArylicError.connectionFailed(error.localizedDescription))
                case .waiting(let error):
                    state.markResumed()
                    continuation.resume(throwing: ArylicError.connectionFailed("Connection waiting: \(error.localizedDescription)"))
                default:
                    break
                }
            }
            
            connection.start(queue: .global())
        }
    }
    
    /// Sends data over TCP connection.
    ///
    /// - Parameters:
    ///   - data: Data to send
    ///   - connection: NWConnection to send on
    /// - Throws: ArylicError.connectionFailed if send fails
    private func send(data: Data, on connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error = error {
                    continuation.resume(throwing: ArylicError.connectionFailed("Send failed: \(error.localizedDescription)"))
                } else {
                    continuation.resume()
                }
            })
        }
    }

    /// Sends data as the final message on a TCP connection.
    ///
    /// Uses `.finalMessage` content context which signals Network.framework to flush all
    /// data to the wire and gracefully close the write side before the connection is cancelled.
    /// This ensures fire-and-forget commands (SET volume/mute) are fully transmitted.
    ///
    /// - Parameters:
    ///   - data: Data to send
    ///   - connection: NWConnection to send on
    /// - Throws: ArylicError.connectionFailed if send fails
    private func sendFinal(data: Data, on connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(
                content: data,
                contentContext: .finalMessage,
                isComplete: true,
                completion: .contentProcessed { error in
                    if let error = error {
                        continuation.resume(throwing: ArylicError.connectionFailed("Send failed: \(error.localizedDescription)"))
                    } else {
                        continuation.resume()
                    }
                }
            )
        }
    }
    
    /// Receives data from TCP connection.
    ///
    /// - Parameter connection: NWConnection to receive from
    /// - Returns: Received data
    /// - Throws: ArylicError.connectionFailed if receive fails
    private func receive(on connection: NWConnection) async throws -> Data {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
                if let error = error {
                    continuation.resume(throwing: ArylicError.connectionFailed("Receive failed: \(error.localizedDescription)"))
                } else if let data = data, !data.isEmpty {
                    continuation.resume(returning: data)
                } else if isComplete {
                    continuation.resume(throwing: ArylicError.invalidResponse("Connection closed with no data"))
                } else {
                    continuation.resume(throwing: ArylicError.invalidResponse("No data received"))
                }
            }
        }
    }
    
    /// Executes an async operation with a timeout.
    ///
    /// - Parameters:
    ///   - seconds: Timeout duration in seconds
    ///   - operation: Async operation to execute
    /// - Returns: Result of the operation
    /// - Throws: ArylicError.timeout if operation exceeds timeout, or original error from operation
    private func withTimeout<T: Sendable>(seconds: TimeInterval, operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw ArylicError.timeout
            }
            
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}

#endif
