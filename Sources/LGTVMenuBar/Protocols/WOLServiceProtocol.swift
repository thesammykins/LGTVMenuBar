import Foundation

/// Protocol for Wake-on-LAN services to wake LG TVs
@preconcurrency public protocol WOLServiceProtocol: Sendable {
    /// Send Wake-on-LAN magic packet to the specified MAC address
    /// 
    /// This method creates and broadcasts a WOL magic packet to wake a TV on the network.
    /// The magic packet is sent via UDP broadcast to port 9, which is the standard
    /// WOL port. The packet contains 6 bytes of 0xFF followed by the MAC address
    /// repeated 16 times.
    /// 
    /// - Parameter macAddress: The MAC address of the TV to wake (format: "AA:BB:CC:DD:EE:FF" or "AABBCCDDEEFF")
    /// - Throws: LGTVError.wolError if the wake operation fails
    func sendWakeRequest(to configuration: TVConfiguration) async throws
    func sendWakeOnLAN(macAddress: String) async throws
}
