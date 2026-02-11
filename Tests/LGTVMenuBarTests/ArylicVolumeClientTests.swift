#if LOCAL_ARYLIC_BUILD

import Foundation
import Testing
@testable import LGTVMenuBar

// MARK: - ArylicVolumeClient TCP Packet Tests

@Suite("ArylicVolumeClient TCP Packet Tests")
struct ArylicVolumeClientTests {
    
    // MARK: - Packet Building Tests
    
    @Test("buildPacket with simple command MCU+VOL+GET")
    func testBuildPacketSimpleCommand() {
        let command = "MCU+VOL+GET"
        let packet = ArylicVolumeClient.buildPacket(command: command)
        
        // Verify header (bytes 0-3)
        let expectedHeader: [UInt8] = [0x18, 0x96, 0x18, 0x20]
        let actualHeader = Array(packet.prefix(4))
        #expect(actualHeader == expectedHeader)
        
        // Verify length (bytes 4-7, little-endian)
        let lengthBytes = packet[4..<8]
        let length = lengthBytes.withUnsafeBytes { bytes in
            bytes.loadUnaligned(as: UInt32.self).littleEndian
        }
        #expect(length == UInt32(command.utf8.count))
        
        // Verify checksum (bytes 8-11, little-endian)
        let checksumBytes = packet[8..<12]
        let checksum = checksumBytes.withUnsafeBytes { bytes in
            bytes.loadUnaligned(as: UInt32.self).littleEndian
        }
        let expectedChecksum = command.utf8.reduce(UInt32(0)) { $0 &+ UInt32($1) }
        #expect(checksum == expectedChecksum)
        
        // Verify reserved bytes (bytes 12-19, all zeros)
        let reservedBytes = Array(packet[12..<20])
        #expect(reservedBytes == [0, 0, 0, 0, 0, 0, 0, 0])
        
        // Verify payload (bytes 20+)
        let payloadData = packet[20...]
        let payload = String(data: payloadData, encoding: .utf8)
        #expect(payload == command)
        
        // Verify total packet length
        #expect(packet.count == 20 + command.utf8.count)
    }
    
    @Test("buildPacket with passthrough volume set command")
    func testBuildPacketPassthroughVolumeSet() {
        let command = "MCU+PAS+RAKOIT:VOL:50&"
        let packet = ArylicVolumeClient.buildPacket(command: command)
        
        // Verify header
        let expectedHeader: [UInt8] = [0x18, 0x96, 0x18, 0x20]
        let actualHeader = Array(packet.prefix(4))
        #expect(actualHeader == expectedHeader)
        
        // Verify length
        let lengthBytes = packet[4..<8]
        let length = lengthBytes.withUnsafeBytes { bytes in
            bytes.loadUnaligned(as: UInt32.self).littleEndian
        }
        #expect(length == UInt32(command.utf8.count))
        
        // Verify checksum
        let checksumBytes = packet[8..<12]
        let checksum = checksumBytes.withUnsafeBytes { bytes in
            bytes.loadUnaligned(as: UInt32.self).littleEndian
        }
        let expectedChecksum = command.utf8.reduce(UInt32(0)) { $0 &+ UInt32($1) }
        #expect(checksum == expectedChecksum)
        
        // Verify payload
        let payloadData = packet[20...]
        let payload = String(data: payloadData, encoding: .utf8)
        #expect(payload == command)
    }
    
    @Test("buildPacket with passthrough mute command")
    func testBuildPacketPassthroughMute() {
        let command = "MCU+PAS+RAKOIT:MUT:1&"
        let packet = ArylicVolumeClient.buildPacket(command: command)
        
        // Verify header
        let expectedHeader: [UInt8] = [0x18, 0x96, 0x18, 0x20]
        let actualHeader = Array(packet.prefix(4))
        #expect(actualHeader == expectedHeader)
        
        // Verify length
        let lengthBytes = packet[4..<8]
        let length = lengthBytes.withUnsafeBytes { bytes in
            bytes.loadUnaligned(as: UInt32.self).littleEndian
        }
        #expect(length == UInt32(command.utf8.count))
        
        // Verify payload
        let payloadData = packet[20...]
        let payload = String(data: payloadData, encoding: .utf8)
        #expect(payload == command)
    }
    
    @Test("buildPacket with passthrough volume GET command")
    func testBuildPacketPassthroughVolumeGet() {
        let command = "MCU+PAS+RAKOIT:VOL&"
        let packet = ArylicVolumeClient.buildPacket(command: command)
        
        // Passthrough GET is >11 bytes, needs & terminator
        #expect(command.utf8.count > 11)
        
        // Verify payload
        let payloadData = packet[20...]
        let payload = String(data: payloadData, encoding: .utf8)
        #expect(payload == command)
    }
    
    @Test("buildPacket with empty command")
    func testBuildPacketEmptyCommand() {
        let command = ""
        let packet = ArylicVolumeClient.buildPacket(command: command)
        
        // Verify header
        let expectedHeader: [UInt8] = [0x18, 0x96, 0x18, 0x20]
        let actualHeader = Array(packet.prefix(4))
        #expect(actualHeader == expectedHeader)
        
        // Verify length is zero
        let lengthBytes = packet[4..<8]
        let length = lengthBytes.withUnsafeBytes { bytes in
            bytes.loadUnaligned(as: UInt32.self).littleEndian
        }
        #expect(length == 0)
        
        // Verify checksum is zero
        let checksumBytes = packet[8..<12]
        let checksum = checksumBytes.withUnsafeBytes { bytes in
            bytes.loadUnaligned(as: UInt32.self).littleEndian
        }
        #expect(checksum == 0)
        
        // Verify packet is exactly 20 bytes (header only)
        #expect(packet.count == 20)
    }
    
    // MARK: - Response Parsing Tests
    
    @Test("parseResponsePayload with valid passthrough response")
    func testParseResponsePayloadValid() throws {
        let responsePayload = "MCU+PAS+RAKOIT:VOL:50&"
        let packet = ArylicVolumeClient.buildPacket(command: responsePayload)
        
        let parsed = try ArylicVolumeClient.parseResponsePayload(from: packet)
        #expect(parsed == responsePayload)
    }
    
    @Test("parseResponsePayload with packet too short")
    func testParseResponsePayloadTooShort() {
        let shortPacket = Data([0x18, 0x96, 0x18, 0x20, 0x00, 0x00, 0x00]) // Only 7 bytes
        
        do {
            _ = try ArylicVolumeClient.parseResponsePayload(from: shortPacket)
            #expect(Bool(false), "Expected error to be thrown")
        } catch let error as ArylicError {
            #expect(error == .invalidResponse("Response packet too short (< 20 bytes)"))
        } catch {
            #expect(Bool(false), "Expected ArylicError")
        }
    }
    
    @Test("parseResponsePayload with invalid header")
    func testParseResponsePayloadInvalidHeader() {
        var packet = Data()
        packet.append(contentsOf: [0xFF, 0xFF, 0xFF, 0xFF]) // Wrong header
        packet.append(contentsOf: [0x0B, 0x00, 0x00, 0x00]) // Length: 11
        packet.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // Checksum
        packet.append(contentsOf: [0, 0, 0, 0, 0, 0, 0, 0]) // Reserved
        packet.append(contentsOf: "MCU+VOL+GET".utf8)
        
        do {
            _ = try ArylicVolumeClient.parseResponsePayload(from: packet)
            #expect(Bool(false), "Expected error to be thrown")
        } catch let error as ArylicError {
            #expect(error == .invalidResponse("Invalid packet header"))
        } catch {
            #expect(Bool(false), "Expected ArylicError")
        }
    }
    
    @Test("parseResponsePayload with incomplete packet")
    func testParseResponsePayloadIncomplete() {
        var packet = Data()
        packet.append(contentsOf: [0x18, 0x96, 0x18, 0x20]) // Header
        packet.append(contentsOf: [0x64, 0x00, 0x00, 0x00]) // Length: 100 (but we won't include that much data)
        packet.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // Checksum
        packet.append(contentsOf: [0, 0, 0, 0, 0, 0, 0, 0]) // Reserved
        packet.append(contentsOf: "MCU+VOL+GET".utf8) // Only 11 bytes, not 100
        
        do {
            _ = try ArylicVolumeClient.parseResponsePayload(from: packet)
            #expect(Bool(false), "Expected error to be thrown")
        } catch let error as ArylicError {
            if case .invalidResponse(let message) = error {
                #expect(message.contains("incomplete"))
            } else {
                #expect(Bool(false), "Expected invalidResponse error with 'incomplete' message")
            }
        } catch {
            #expect(Bool(false), "Expected ArylicError")
        }
    }
    
    // MARK: - Volume Parsing Tests (Passthrough Format)
    
    @Test("parseVolumeValue with MCU+PAS+RAKOIT:VOL:50&")
    func testParseVolumeValue50() throws {
        let response = "MCU+PAS+RAKOIT:VOL:50&"
        let volume = try ArylicVolumeClient.parseVolumeValue(from: response)
        #expect(volume == 50)
    }
    
    @Test("parseVolumeValue with MCU+PAS+RAKOIT:VOL:0&")
    func testParseVolumeValue0() throws {
        let response = "MCU+PAS+RAKOIT:VOL:0&"
        let volume = try ArylicVolumeClient.parseVolumeValue(from: response)
        #expect(volume == 0)
    }
    
    @Test("parseVolumeValue with MCU+PAS+RAKOIT:VOL:100&")
    func testParseVolumeValue100() throws {
        let response = "MCU+PAS+RAKOIT:VOL:100&"
        let volume = try ArylicVolumeClient.parseVolumeValue(from: response)
        #expect(volume == 100)
    }
    
    @Test("parseVolumeValue without trailing ampersand")
    func testParseVolumeValueNoAmpersand() throws {
        let response = "MCU+PAS+RAKOIT:VOL:30"
        let volume = try ArylicVolumeClient.parseVolumeValue(from: response)
        #expect(volume == 30)
    }
    
    @Test("parseVolumeValue with invalid format")
    func testParseVolumeValueInvalidFormat() {
        let response = "INVALID"
        
        do {
            _ = try ArylicVolumeClient.parseVolumeValue(from: response)
            #expect(Bool(false), "Expected error to be thrown")
        } catch let error as ArylicError {
            if case .invalidResponse(let message) = error {
                #expect(message.contains("Invalid volume response format"))
            } else {
                #expect(Bool(false), "Expected invalidResponse error")
            }
        } catch {
            #expect(Bool(false), "Expected ArylicError")
        }
    }
    
    @Test("parseVolumeValue with old AXX format rejects")
    func testParseVolumeValueRejectsOldFormat() {
        let response = "AXX+VOL+030"
        
        do {
            _ = try ArylicVolumeClient.parseVolumeValue(from: response)
            #expect(Bool(false), "Expected error to be thrown")
        } catch let error as ArylicError {
            if case .invalidResponse(let message) = error {
                #expect(message.contains("Invalid volume response format"))
            } else {
                #expect(Bool(false), "Expected invalidResponse error")
            }
        } catch {
            #expect(Bool(false), "Expected ArylicError")
        }
    }
    
    @Test("parseVolumeValue with non-numeric value")
    func testParseVolumeValueNonNumeric() {
        let response = "MCU+PAS+RAKOIT:VOL:abc&"
        
        do {
            _ = try ArylicVolumeClient.parseVolumeValue(from: response)
            #expect(Bool(false), "Expected error to be thrown")
        } catch let error as ArylicError {
            if case .invalidResponse(let message) = error {
                #expect(message.contains("Invalid volume response format"))
            } else {
                #expect(Bool(false), "Expected invalidResponse error")
            }
        } catch {
            #expect(Bool(false), "Expected ArylicError")
        }
    }
    
    // MARK: - Mute Parsing Tests (Passthrough Format)
    
    @Test("parseMuteValue with MCU+PAS+RAKOIT:MUT:1& returns true")
    func testParseMuteValueTrue() throws {
        let response = "MCU+PAS+RAKOIT:MUT:1&"
        let muted = try ArylicVolumeClient.parseMuteValue(from: response)
        #expect(muted == true)
    }
    
    @Test("parseMuteValue with MCU+PAS+RAKOIT:MUT:0& returns false")
    func testParseMuteValueFalse() throws {
        let response = "MCU+PAS+RAKOIT:MUT:0&"
        let muted = try ArylicVolumeClient.parseMuteValue(from: response)
        #expect(muted == false)
    }
    
    @Test("parseMuteValue without trailing ampersand")
    func testParseMuteValueNoAmpersand() throws {
        let response = "MCU+PAS+RAKOIT:MUT:1"
        let muted = try ArylicVolumeClient.parseMuteValue(from: response)
        #expect(muted == true)
    }
    
    @Test("parseMuteValue with invalid format")
    func testParseMuteValueInvalidFormat() {
        let response = "INVALID"
        
        do {
            _ = try ArylicVolumeClient.parseMuteValue(from: response)
            #expect(Bool(false), "Expected error to be thrown")
        } catch let error as ArylicError {
            if case .invalidResponse(let message) = error {
                #expect(message.contains("Invalid mute response format"))
            } else {
                #expect(Bool(false), "Expected invalidResponse error")
            }
        } catch {
            #expect(Bool(false), "Expected ArylicError")
        }
    }
    
    @Test("parseMuteValue with old AXX format rejects")
    func testParseMuteValueRejectsOldFormat() {
        let response = "AXX+MUT+001"
        
        do {
            _ = try ArylicVolumeClient.parseMuteValue(from: response)
            #expect(Bool(false), "Expected error to be thrown")
        } catch let error as ArylicError {
            if case .invalidResponse(let message) = error {
                #expect(message.contains("Invalid mute response format"))
            } else {
                #expect(Bool(false), "Expected invalidResponse error")
            }
        } catch {
            #expect(Bool(false), "Expected ArylicError")
        }
    }
    
    @Test("parseMuteValue with non-numeric value")
    func testParseMuteValueNonNumeric() {
        let response = "MCU+PAS+RAKOIT:MUT:abc&"
        
        do {
            _ = try ArylicVolumeClient.parseMuteValue(from: response)
            #expect(Bool(false), "Expected error to be thrown")
        } catch let error as ArylicError {
            if case .invalidResponse(let message) = error {
                #expect(message.contains("Invalid mute response format"))
            } else {
                #expect(Bool(false), "Expected invalidResponse error")
            }
        } catch {
            #expect(Bool(false), "Expected ArylicError")
        }
    }
    
    // MARK: - Round-trip Tests
    
    @Test("Round-trip: build passthrough packet then parse payload")
    func testRoundTripBuildAndParse() throws {
        let originalCommand = "MCU+PAS+RAKOIT:VOL&"
        
        let packet = ArylicVolumeClient.buildPacket(command: originalCommand)
        let parsedPayload = try ArylicVolumeClient.parseResponsePayload(from: packet)
        
        #expect(parsedPayload == originalCommand)
    }
    
    @Test("Round-trip: build passthrough volume response, parse, extract volume")
    func testRoundTripVolumeCommand() throws {
        let volumeResponse = "MCU+PAS+RAKOIT:VOL:75&"
        
        let packet = ArylicVolumeClient.buildPacket(command: volumeResponse)
        let payload = try ArylicVolumeClient.parseResponsePayload(from: packet)
        let volume = try ArylicVolumeClient.parseVolumeValue(from: payload)
        
        #expect(volume == 75)
    }
    
    @Test("Round-trip: build passthrough mute response, parse, extract mute state")
    func testRoundTripMuteCommand() throws {
        let muteResponse = "MCU+PAS+RAKOIT:MUT:1&"
        
        let packet = ArylicVolumeClient.buildPacket(command: muteResponse)
        let payload = try ArylicVolumeClient.parseResponsePayload(from: packet)
        let muted = try ArylicVolumeClient.parseMuteValue(from: payload)
        
        #expect(muted == true)
    }
}

#endif
