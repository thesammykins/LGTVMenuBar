import Foundation
import Darwin
import OSLog

struct WOLTarget: Hashable, Sendable {
    let host: String
    let port: UInt16
    let interfaceName: String?
}

struct NetworkInterfaceSnapshot: Hashable, Sendable {
    let name: String
    let address: String
    let netmask: String
    let broadcastAddress: String?

    init(name: String, address: String, netmask: String, broadcastAddress: String? = nil) {
        self.name = name
        self.address = address
        self.netmask = netmask
        self.broadcastAddress = broadcastAddress
    }
}

/// Production implementation of WOLServiceProtocol using UDP broadcast.
///
/// Wake reliability depends on the TV staying reachable in standby network mode.
/// To match the behavior of mature LG integrations, wake packets are sent to all
/// useful local broadcast targets and both common WOL ports before WebOS pairing
/// is attempted.
public final class WOLService: WOLServiceProtocol, @unchecked Sendable {

    typealias InterfaceProvider = () -> [NetworkInterfaceSnapshot]
    typealias PacketSender = (Data, WOLTarget) async throws -> Void

    // MARK: - Constants

    static let wolPort: UInt16 = 9
    static let alternateWOLPort: UInt16 = 7
    static let broadcastAddress = "255.255.255.255"
    static let synchronizationStream = Data(repeating: 0xFF, count: 6)
    static let macRepeatCount = 16
    static let sendAttemptCount = 3
    static let retryDelay: Duration = .milliseconds(250)
    static let defaultWakeTimeoutSeconds: Double = 90

    // MARK: - Properties

    private let logger = Logger(subsystem: "com.lgtvmenubar", category: "WOLService")
    private let interfaceProvider: InterfaceProvider
    private let packetSender: PacketSender

    // MARK: - Initialization

    public init() {
        let queue = DispatchQueue(label: "com.lgtvmenubar.wol.network", qos: .userInitiated)
        self.interfaceProvider = Self.activeIPv4Interfaces
        self.packetSender = { packet, target in
            try await Self.sendUDPPacket(packet, to: target, queue: queue)
        }
    }

    init(
        interfaceProvider: @escaping InterfaceProvider,
        packetSender: @escaping PacketSender
    ) {
        self.interfaceProvider = interfaceProvider
        self.packetSender = packetSender
    }

    // MARK: - WOLServiceProtocol Implementation

    public func sendWakeRequest(to configuration: TVConfiguration) async throws {
        do {
            let normalizedMAC = try validateAndNormalizeMACAddress(configuration.macAddress)
            let magicPacket = try createMagicPacket(macAddress: normalizedMAC)
            let targets = wakeTargets(for: configuration)
            let targetSummary = targets.map { "\($0.host):\($0.port)\($0.interfaceName.map { " via \($0)" } ?? "")" }.joined(separator: ", ")

            logger.info("Sending Wake-on-LAN to \(configuration.name, privacy: .public) targets: \(targetSummary, privacy: .public)")
            try await sendMagicPacket(magicPacket, to: targets)
        } catch {
            throw LGTVError.wolError(error)
        }
    }

    public func sendWakeOnLAN(macAddress: String) async throws {
        let configuration = TVConfiguration(
            name: "Wake Target",
            ipAddress: "",
            macAddress: macAddress
        )
        try await sendWakeRequest(to: configuration)
    }

    public func wakeDiagnostics(for configuration: TVConfiguration) -> [String: String] {
        let interfaces = interfaceProvider()
        let targets = wakeTargets(for: configuration, interfaces: interfaces)
        let sameSubnetInterfaces = interfaces
            .filter { Self.isSameSubnet(configuration.ipAddress, $0.address, $0.netmask) }
            .map(\.name)

        var metadata: [String: String] = [
            "configuredMAC": configuration.macAddress,
            "configuredBroadcastAddress": normalizedOptionalString(configuration.wakeBroadcastAddress) ?? "auto",
            "configuredWakePort": configuration.wakePort.map(String.init) ?? "auto",
            "wakeTimeoutSeconds": "\(effectiveWakeTimeoutSeconds(for: configuration))",
            "wakeTargets": targets.map { "\($0.host):\($0.port)" }.joined(separator: ","),
            "activeInterfaces": interfaces.map { "\($0.name)=\($0.address)/\($0.netmask)" }.joined(separator: ","),
            "sameSubnetInterfaces": sameSubnetInterfaces.isEmpty ? "none" : sameSubnetInterfaces.joined(separator: ","),
            "requiredTVSettings": "TV On With Mobile / Turn On via Wi-Fi enabled; LG Connect Apps/Mobile App enabled; Quick Start+/Always Ready may affect standby behavior",
            "networkStandbyLimit": "Cannot wake a TV from true deep-off, unplugged, or power-saving states without a standby network, CEC, or IR path"
        ]

        if let arp = Self.arpEntry(for: configuration.ipAddress) {
            metadata["arpObservedMAC"] = arp.macAddress
            metadata["arpInterface"] = arp.interfaceName ?? "unknown"
        } else {
            metadata["arpObservedMAC"] = "unavailable"
        }

        return metadata
    }

    // MARK: - Target Resolution

    private func wakeTargets(for configuration: TVConfiguration) -> [WOLTarget] {
        wakeTargets(for: configuration, interfaces: interfaceProvider())
    }

    private func wakeTargets(
        for configuration: TVConfiguration,
        interfaces: [NetworkInterfaceSnapshot]
    ) -> [WOLTarget] {
        let ports = wakePorts(for: configuration)

        if let explicitBroadcast = normalizedOptionalString(configuration.wakeBroadcastAddress) {
            return ports.map { WOLTarget(host: explicitBroadcast, port: $0, interfaceName: nil) }
        }

        var targets: [WOLTarget] = []
        let matchingInterfaces = interfaces.filter {
            Self.isSameSubnet(configuration.ipAddress, $0.address, $0.netmask)
        }

        appendTargets(
            to: &targets,
            hosts: [Self.broadcastAddress],
            ports: ports,
            interfaceName: nil
        )

        for interface in matchingInterfaces {
            if let broadcast = interface.broadcastAddress {
                appendTargets(
                    to: &targets,
                    hosts: [broadcast],
                    ports: ports,
                    interfaceName: interface.name
                )
            }
        }

        if targets.contains(where: { $0.host != Self.broadcastAddress }) == false,
           let derivedBroadcast = Self.derivedSubnetBroadcast(for: configuration.ipAddress) {
            appendTargets(
                to: &targets,
                hosts: [derivedBroadcast],
                ports: ports,
                interfaceName: matchingInterfaces.first?.name
            )
        }

        return uniqueTargets(targets)
    }

    private func wakePorts(for configuration: TVConfiguration) -> [UInt16] {
        if let configuredPort = configuration.wakePort,
           configuredPort > 0,
           configuredPort <= Int(UInt16.max) {
            return [UInt16(configuredPort)]
        }

        return [Self.wolPort, Self.alternateWOLPort]
    }

    private func appendTargets(
        to targets: inout [WOLTarget],
        hosts: [String],
        ports: [UInt16],
        interfaceName: String?
    ) {
        for host in hosts where !host.isEmpty {
            for port in ports {
                targets.append(WOLTarget(host: host, port: port, interfaceName: interfaceName))
            }
        }
    }

    private func uniqueTargets(_ targets: [WOLTarget]) -> [WOLTarget] {
        var seen: Set<WOLTarget> = []
        var unique: [WOLTarget] = []

        for target in targets {
            guard seen.insert(target).inserted else { continue }
            unique.append(target)
        }

        return unique
    }

    private func effectiveWakeTimeoutSeconds(for configuration: TVConfiguration) -> Double {
        guard let configured = configuration.wakeTimeoutSeconds, configured > 0 else {
            return Self.defaultWakeTimeoutSeconds
        }
        return configured
    }

    private func normalizedOptionalString(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Packet Creation

    private func validateAndNormalizeMACAddress(_ macAddress: String) throws -> String {
        let cleaned = macAddress
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: " ", with: "")
            .uppercased()

        guard cleaned.count == 12 else {
            throw WOLError.invalidMACAddress(
                macAddress,
                "MAC address must be 12 hexadecimal characters"
            )
        }

        let hexCharacterSet = CharacterSet(charactersIn: "0123456789ABCDEF")
        guard cleaned.unicodeScalars.allSatisfy({ hexCharacterSet.contains($0) }) else {
            throw WOLError.invalidMACAddress(
                macAddress,
                "MAC address contains invalid hexadecimal characters"
            )
        }

        return cleaned
    }

    private func createMagicPacket(macAddress: String) throws -> Data {
        var packet = Data()
        packet.append(Self.synchronizationStream)

        guard let macData = parseMACAddressToBytes(macAddress) else {
            throw WOLError.packetCreationFailed("Failed to parse MAC address bytes")
        }

        for _ in 0..<Self.macRepeatCount {
            packet.append(macData)
        }

        guard packet.count == 102 else {
            throw WOLError.packetCreationFailed(
                "Invalid packet size: \(packet.count) bytes (expected 102)"
            )
        }

        return packet
    }

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

    // MARK: - Packet Sending

    private func sendMagicPacket(_ packet: Data, to targets: [WOLTarget]) async throws {
        guard !targets.isEmpty else {
            throw WOLError.broadcastFailed
        }

        var lastError: Error?
        var successfulSendCount = 0

        for target in targets {
            for attempt in 1...Self.sendAttemptCount {
                do {
                    try await packetSender(packet, target)
                    successfulSendCount += 1
                } catch {
                    lastError = error
                    logger.warning("Wake-on-LAN send failed for \(target.host, privacy: .public):\(target.port, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }

                if attempt < Self.sendAttemptCount {
                    try? await Task.sleep(for: Self.retryDelay)
                }
            }
        }

        guard successfulSendCount > 0 else {
            if let lastError {
                throw lastError
            }
            throw WOLError.broadcastFailed
        }
    }

    private static func sendUDPPacket(
        _ packet: Data,
        to target: WOLTarget,
        queue: DispatchQueue
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    try Self.sendUDPPacketSynchronously(packet, to: target)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func sendUDPPacketSynchronously(_ packet: Data, to target: WOLTarget) throws {
        let socketDescriptor = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard socketDescriptor >= 0 else {
            throw WOLError.networkError(Self.posixError())
        }
        defer { close(socketDescriptor) }

        var broadcastEnabled: Int32 = 1
        setsockopt(
            socketDescriptor,
            SOL_SOCKET,
            SO_BROADCAST,
            &broadcastEnabled,
            socklen_t(MemoryLayout.size(ofValue: broadcastEnabled))
        )

        if let interfaceName = target.interfaceName {
            var interfaceIndex = if_nametoindex(interfaceName)
            if interfaceIndex > 0 {
                setsockopt(
                    socketDescriptor,
                    IPPROTO_IP,
                    IP_BOUND_IF,
                    &interfaceIndex,
                    socklen_t(MemoryLayout.size(ofValue: interfaceIndex))
                )
            }
        }

        var socketAddress = sockaddr_in()
        socketAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        socketAddress.sin_family = sa_family_t(AF_INET)
        socketAddress.sin_port = target.port.bigEndian

        let parseResult = target.host.withCString { hostPointer in
            inet_pton(AF_INET, hostPointer, &socketAddress.sin_addr)
        }
        guard parseResult == 1 else {
            throw WOLError.networkError(NSError(
                domain: NSURLErrorDomain,
                code: NSURLErrorBadURL,
                userInfo: [NSLocalizedDescriptionKey: "Invalid IPv4 address: \(target.host)"]
            ))
        }

        let sentByteCount = packet.withUnsafeBytes { packetBytes -> Int in
            guard let baseAddress = packetBytes.baseAddress else { return -1 }
            return withUnsafePointer(to: &socketAddress) { addressPointer in
                addressPointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                    sendto(
                        socketDescriptor,
                        baseAddress,
                        packetBytes.count,
                        0,
                        sockaddrPointer,
                        socklen_t(MemoryLayout<sockaddr_in>.size)
                    )
                }
            }
        }

        guard sentByteCount == packet.count else {
            throw WOLError.networkError(Self.posixError())
        }
    }

    // MARK: - Interface and ARP Diagnostics

    private static func activeIPv4Interfaces() -> [NetworkInterfaceSnapshot] {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddress = ifaddr else {
            return []
        }
        defer { freeifaddrs(ifaddr) }

        var snapshots: [NetworkInterfaceSnapshot] = []
        var pointer: UnsafeMutablePointer<ifaddrs>? = firstAddress

        while let currentPointer = pointer {
            defer { pointer = currentPointer.pointee.ifa_next }

            let interface = currentPointer.pointee
            guard let addressPointer = interface.ifa_addr,
                  addressPointer.pointee.sa_family == sa_family_t(AF_INET) else {
                continue
            }

            let flags = Int32(interface.ifa_flags)
            guard flags & IFF_UP != 0,
                  flags & IFF_RUNNING != 0,
                  flags & IFF_LOOPBACK == 0 else {
                continue
            }

            let name = String(cString: interface.ifa_name)
            guard let address = ipv4String(from: interface.ifa_addr),
                  let netmask = ipv4String(from: interface.ifa_netmask) else {
                continue
            }

            let broadcast: String?
            if flags & IFF_BROADCAST != 0 {
                broadcast = ipv4String(from: interface.ifa_dstaddr)
            } else {
                broadcast = nil
            }

            snapshots.append(NetworkInterfaceSnapshot(
                name: name,
                address: address,
                netmask: netmask,
                broadcastAddress: broadcast
            ))
        }

        var seen: Set<NetworkInterfaceSnapshot> = []
        return snapshots.filter { seen.insert($0).inserted }
    }

    private static func ipv4String(from sockaddrPointer: UnsafePointer<sockaddr>?) -> String? {
        guard let sockaddrPointer else { return nil }

        var address = sockaddrPointer.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
            $0.pointee.sin_addr
        }
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))

        guard inet_ntop(AF_INET, &address, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else {
            return nil
        }

        let endIndex = buffer.firstIndex(of: 0) ?? buffer.endIndex
        return String(decoding: buffer[..<endIndex].map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    private static func arpEntry(for ipAddress: String) -> (macAddress: String, interfaceName: String?)? {
        guard !ipAddress.isEmpty else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/arp")
        process.arguments = ["-an", ipAddress]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8),
              output.contains(" at "),
              !output.contains("(incomplete)") else {
            return nil
        }

        let parts = output.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).map(String.init)
        guard let atIndex = parts.firstIndex(of: "at"),
              parts.indices.contains(atIndex + 1) else {
            return nil
        }

        let macAddress = parts[atIndex + 1]
        let interfaceName: String?
        if let onIndex = parts.firstIndex(of: "on"), parts.indices.contains(onIndex + 1) {
            interfaceName = parts[onIndex + 1]
        } else {
            interfaceName = nil
        }

        return (macAddress, interfaceName)
    }

    // MARK: - IPv4 Helpers

    private static func isSameSubnet(_ ipAddress: String, _ interfaceAddress: String, _ netmask: String) -> Bool {
        guard let ip = ipv4Value(ipAddress),
              let address = ipv4Value(interfaceAddress),
              let mask = ipv4Value(netmask) else {
            return false
        }

        return (ip & mask) == (address & mask)
    }

    private static func derivedSubnetBroadcast(for ipAddress: String) -> String? {
        guard var octets = ipv4Octets(ipAddress), octets.count == 4 else {
            return nil
        }

        octets[3] = 255
        return octets.map(String.init).joined(separator: ".")
    }

    private static func ipv4Value(_ address: String) -> UInt32? {
        guard let octets = ipv4Octets(address), octets.count == 4 else {
            return nil
        }

        return octets.reduce(UInt32(0)) { value, octet in
            (value << 8) | UInt32(octet)
        }
    }

    private static func ipv4Octets(_ address: String) -> [UInt8]? {
        let parts = address.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }

        return parts.compactMap { part in
            guard let value = UInt8(String(part)) else { return nil }
            return value
        }
    }

    private static func posixError() -> NSError {
        NSError(
            domain: NSPOSIXErrorDomain,
            code: Int(errno),
            userInfo: [NSLocalizedDescriptionKey: String(cString: strerror(errno))]
        )
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
