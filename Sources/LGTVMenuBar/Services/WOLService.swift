import Foundation
import Network
import OSLog

/// Production implementation of WOLServiceProtocol using Network framework
/// 
/// This service provides Wake-on-LAN functionality for LG TVs using UDP broadcasting.
/// It creates magic packets according to WOL specification and broadcasts them
/// on port 9 to wake devices on the local network.
/// 
/// The magic packet format:
/// - 6 bytes of 0xFF (synchronization stream)
/// - Target MAC address repeated 16 times (96 bytes total)
/// - Total packet size: 102 bytes
/// 
/// Network details:
/// - Protocol: UDP
/// - Port: 9 (standard WOL port)
/// - Broadcast: 255.255.255.255 (limited broadcast)
/// - Transport: IPv4 UDP datagram
/// 
/// This implementation uses the modern Network framework which provides:
/// - Better error handling and diagnostics
/// - Automatic interface selection
/// - Proper concurrency support with Swift 6
/// - Built-in path monitoring and failure handling
/// 
/// Note: This class is designed to be thread-safe without requiring actor isolation
/// by using immutable constants and proper synchronization for network operations.
public final class WOLService: WOLServiceProtocol {
    
    // MARK: - Constants
    
    /// Standard Wake-on-LAN port
    static let wolPort: UInt16 = 9
    
    /// Broadcast address for WOL packets (limited broadcast)
    static let broadcastAddress = "255.255.255.255"
    
    /// Magic packet synchronization stream (6 bytes of 0xFF)
    static let synchronizationStream = Data(repeating: 0xFF, count: 6)
    
    /// Number of times MAC address is repeated in magic packet
    static let macRepeatCount = 16
    
    // MARK: - Properties
    
    /// Queue for network operations
    private let networkQueue = DispatchQueue(label: "com.lgtvmenubar.wol.network", qos: .userInitiated)
    
    // MARK: - Initialization
    
    /// Initialize a new WOLService instance
    public init() {}
    
    // MARK: - WOLServiceProtocol Implementation
    
    /// Send Wake-on-LAN magic packet to the specified TV configuration
    /// 
    /// This method validates the MAC address format from the TV configuration,
    /// constructs a WOL magic packet, and broadcasts it via UDP to port 9.
    /// The operation is performed asynchronously using the Network framework
    /// for proper error handling and concurrency.
    /// 
    /// The magic packet construction follows the WOL specification:
    /// 1. Create 6-byte synchronization stream (0xFF repeated 6 times)
    /// 2. Parse and validate the MAC address from configuration
    /// 3. Repeat the MAC address 16 times
    /// 4. Combine synchronization stream + repeated MAC address
    /// 5. Broadcast via UDP to port 9
    /// 
    /// - Parameter configuration: The TV configuration containing MAC address
    /// - Throws: LGTVError.wolError if the wake operation fails
    public func sendWakeRequest(to configuration: TVConfiguration) async throws {
        try await sendWakeOnLAN(macAddress: configuration.macAddress)
    }
    
    public func sendWakeOnLAN(macAddress: String) async throws {
        do {
            // Validate and normalize MAC address
            let normalizedMAC = try validateAndNormalizeMACAddress(macAddress)
            
            // Create magic packet
            let magicPacket = try createMagicPacket(macAddress: normalizedMAC)
            
            // Send packet via UDP broadcast
            try await sendMagicPacket(magicPacket)
            
        } catch {
            // Wrap any error in LGTVError.wolError
            throw LGTVError.wolError(error)
        }
    }

    
    // MARK: - Private Methods
    
    /// Validate and normalize MAC address format
    /// 
    /// This method accepts various MAC address formats and converts them to
    /// a standardized continuous hex format for packet construction.
    /// 
    /// - Parameter macAddress: The MAC address to validate and normalize
    /// - Returns: Normalized MAC address in continuous hex format
    /// - Throws: WOLError.invalidMACAddress if format is invalid
    private func validateAndNormalizeMACAddress(_ macAddress: String) throws -> String {
        // Remove common separators and whitespace
        let cleaned = macAddress
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: " ", with: "")
            .uppercased()
        
        // Validate length (should be 12 hex characters for 6 bytes)
        guard cleaned.count == 12 else {
            throw WOLError.invalidMACAddress(
                macAddress,
                "MAC address must be 12 hexadecimal characters"
            )
        }
        
        // Validate hex characters
        let hexCharacterSet = CharacterSet(charactersIn: "0123456789ABCDEF")
        guard cleaned.unicodeScalars.allSatisfy({ hexCharacterSet.contains($0) }) else {
            throw WOLError.invalidMACAddress(
                macAddress,
                "MAC address contains invalid hexadecimal characters"
            )
        }
        
        return cleaned
    }
    
    /// Create WOL magic packet from MAC address
    /// 
    /// Constructs the magic packet according to WOL specification:
    /// - 6 bytes of 0xFF (synchronization stream)
    /// - MAC address repeated 16 times
    /// 
    /// - Parameter macAddress: Normalized MAC address (12 hex characters)
    /// - Returns: Magic packet data (102 bytes)
    /// - Throws: WOLError.packetCreationFailed if packet creation fails
    private func createMagicPacket(macAddress: String) throws -> Data {
        var packet = Data()
        
        // Add synchronization stream
        packet.append(Self.synchronizationStream)
        
        // Parse MAC address into bytes
        guard let macData = parseMACAddressToBytes(macAddress) else {
            throw WOLError.packetCreationFailed("Failed to parse MAC address bytes")
        }
        
        // Repeat MAC address 16 times
        for _ in 0..<Self.macRepeatCount {
            packet.append(macData)
        }
        
        // Verify packet size (should be 102 bytes)
        guard packet.count == 102 else {
            throw WOLError.packetCreationFailed(
                "Invalid packet size: \(packet.count) bytes (expected 102)"
            )
        }
        
        return packet
    }
    
    /// Parse MAC address string into Data bytes
    /// 
    /// - Parameter macAddress: Normalized MAC address (12 hex characters)
    /// - Returns: MAC address as 6-byte Data, or nil if parsing fails
    private func parseMACAddressToBytes(_ macAddress: String) -> Data? {
        guard macAddress.count == 12 else { return nil }
        
        var macBytes = Data()
        var index = macAddress.startIndex
        
        for _ in 0..<6 {
            let endIndex = macAddress.index(index, offsetBy: 2)
            let byteString = String(macAddress[index..<endIndex])
            
            guard let byte = UInt8(byteString, radix: 16) else { return nil }
            macBytes.append(byte)
            
            index = endIndex
        }
        
        return macBytes.count == 6 ? macBytes : nil
    }
    
    /// Send magic packet via UDP broadcast
    /// 
    /// Creates a UDP connection to the broadcast address and sends the
    /// magic packet. The connection is created and destroyed for each send
    /// operation to ensure clean state.
    /// 
    /// - Parameter packet: Magic packet data to send
    /// - Throws: WOLError.networkError if sending fails
    private func sendMagicPacket(_ packet: Data) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            networkQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: WOLError.networkError(
                        NSError(domain: NSPOSIXErrorDomain, code: Int(ECONNRESET), userInfo: nil)
                    ))
                    return
                }
                
                // Create UDP connection to broadcast address
                let host = NWEndpoint.Host(Self.broadcastAddress)
                let port = NWEndpoint.Port(rawValue: Self.wolPort)!
                
                let connection = NWConnection(host: host, port: port, using: .udp)
                
                // Set up connection state handler
                connection.stateUpdateHandler = { state in
                    switch state {
                    case .failed(let error):
                        continuation.resume(throwing: WOLError.networkError(error))
                        connection.cancel()
                    case .cancelled:
                        // Connection cancelled, no action needed
                        break
                    case .ready:
                        // Connection ready, send packet
                        connection.send(content: packet, completion: .contentProcessed { error in
                            if let error = error {
                                continuation.resume(throwing: WOLError.networkError(error))
                            } else {
                                continuation.resume()
                            }
                            connection.cancel()
                        })
                    case .waiting(let error):
                        continuation.resume(throwing: WOLError.networkError(error))
                        connection.cancel()
                    case .setup, .preparing:
                        // Connection in progress, wait for state change
                        break
                    @unknown default:
                        continuation.resume(throwing: WOLError.networkError(
                            NSError(domain: NSURLErrorDomain, code: NSURLErrorUnknown, userInfo: nil)
                        ))
                        connection.cancel()
                    }
                }
                
                // Start connection
                connection.start(queue: self.networkQueue)
            }
        }
    }
}

// MARK: - WOL Error Types

/// Wake-on-LAN specific errors
public enum WOLError: Error, LocalizedError, Sendable {
    case invalidMACAddress(String, String? = nil)
    case packetCreationFailed(String)
    case networkError(Error)
    case broadcastFailed
    
    public var errorDescription: String? {
        switch self {
        case .invalidMACAddress(let mac, let details):
            if let details = details {
                return "Invalid MAC address '\(mac)': \(details)"
            } else {
                return "Invalid MAC address: \(mac)"
            }
        case .packetCreationFailed(let details):
            return "Failed to create magic packet: \(details)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .broadcastFailed:
            return "Failed to broadcast wake packet"
        }
    }
}