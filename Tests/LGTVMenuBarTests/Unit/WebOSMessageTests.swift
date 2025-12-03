import Testing
import Foundation
@testable import LGTVMenuBar

@Suite("WebOSMessage Tests")
struct WebOSMessageTests {
    
    // MARK: - WebOSRequest Tests
    
    @Test("WebOSRequest initializes with required properties")
    func requestInitialization() {
        let request = WebOSRequest(
            id: "test_1",
            type: "request",
            uri: "ssap://audio/getVolume"
        )
        
        #expect(request.id == "test_1")
        #expect(request.type == "request")
        #expect(request.uri == "ssap://audio/getVolume")
        #expect(request.payload == nil)
    }
    
    @Test("WebOSRequest initializes with payload")
    func requestWithPayload() {
        let payload: [String: AnyCodable] = [
            "volume": AnyCodable(50),
            "mute": AnyCodable(false)
        ]
        let request = WebOSRequest(
            id: "test_2",
            type: "request",
            uri: "ssap://audio/setVolume",
            payload: payload
        )
        
        #expect(request.payload != nil)
        #expect(request.payload?["volume"]?.value as? Int == 50)
        #expect(request.payload?["mute"]?.value as? Bool == false)
    }
    
    @Test("WebOSRequest encodes to JSON correctly")
    func requestEncodesToJSON() throws {
        let request = WebOSRequest(
            id: "encode_test",
            type: "request",
            uri: "ssap://system/turnOff"
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(request)
        let json = String(data: data, encoding: .utf8)!
        
        #expect(json.contains("encode_test"))
        #expect(json.contains("request"))
        // JSON may escape forward slashes, so check for the URI with either format
        #expect(json.contains("ssap://system/turnOff") || json.contains("ssap:\\/\\/system\\/turnOff"))
    }
    
    @Test("WebOSRequest decodes from JSON correctly")
    func requestDecodesFromJSON() throws {
        let json = """
        {
            "id": "decode_test",
            "type": "subscribe",
            "uri": "ssap://audio/getVolume"
        }
        """
        
        let decoder = JSONDecoder()
        let data = json.data(using: .utf8)!
        let request = try decoder.decode(WebOSRequest.self, from: data)
        
        #expect(request.id == "decode_test")
        #expect(request.type == "subscribe")
        #expect(request.uri == "ssap://audio/getVolume")
    }
    
    @Test("WebOSRequest round-trip preserves data")
    func requestRoundTrip() throws {
        let payload: [String: AnyCodable] = [
            "inputId": AnyCodable("HDMI_1")
        ]
        let original = WebOSRequest(
            id: "roundtrip_1",
            type: "request",
            uri: "ssap://tv/switchInput",
            payload: payload
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(WebOSRequest.self, from: data)
        
        #expect(decoded.id == original.id)
        #expect(decoded.type == original.type)
        #expect(decoded.uri == original.uri)
        #expect(decoded.payload?["inputId"]?.value as? String == "HDMI_1")
    }
    
    // MARK: - WebOSResponse Tests
    
    @Test("WebOSResponse initializes with required properties")
    func responseInitialization() {
        let payload = WebOSResponsePayload(returnValue: true)
        let response = WebOSResponse(
            id: "response_1",
            type: "response",
            payload: payload
        )
        
        #expect(response.id == "response_1")
        #expect(response.type == "response")
        #expect(response.payload.returnValue == true)
    }
    
    @Test("WebOSResponse decodes from JSON correctly")
    func responseDecodesFromJSON() throws {
        let json = """
        {
            "id": "resp_decode",
            "type": "response",
            "payload": {
                "returnValue": true,
                "volume": 25,
                "muted": false
            }
        }
        """
        
        let decoder = JSONDecoder()
        let data = json.data(using: .utf8)!
        let response = try decoder.decode(WebOSResponse.self, from: data)
        
        #expect(response.id == "resp_decode")
        #expect(response.type == "response")
        #expect(response.payload.returnValue == true)
    }
    
    @Test("WebOSResponse decodes error response")
    func responseDecodesError() throws {
        let json = """
        {
            "id": "error_1",
            "type": "error",
            "payload": {
                "returnValue": false
            }
        }
        """
        
        let decoder = JSONDecoder()
        let data = json.data(using: .utf8)!
        let response = try decoder.decode(WebOSResponse.self, from: data)
        
        #expect(response.id == "error_1")
        #expect(response.type == "error")
        #expect(response.payload.returnValue == false)
    }
    
    @Test("WebOSResponse decodes registered response with client key")
    func responseDecodesRegistered() throws {
        let json = """
        {
            "id": "register_0",
            "type": "registered",
            "payload": {
                "returnValue": true,
                "client-key": "abcd1234efgh5678"
            }
        }
        """
        
        let decoder = JSONDecoder()
        let data = json.data(using: .utf8)!
        let response = try decoder.decode(WebOSResponse.self, from: data)
        
        #expect(response.id == "register_0")
        #expect(response.type == "registered")
        #expect(response.payload.returnValue == true)
    }
    
    // MARK: - WebOSResponsePayload Tests
    
    @Test("WebOSResponsePayload with returnValue only")
    func payloadReturnValueOnly() throws {
        let json = """
        {
            "returnValue": true
        }
        """
        
        let decoder = JSONDecoder()
        let data = json.data(using: .utf8)!
        let payload = try decoder.decode(WebOSResponsePayload.self, from: data)
        
        #expect(payload.returnValue == true)
    }
    
    @Test("WebOSResponsePayload with additional data")
    func payloadWithAdditionalData() throws {
        let json = """
        {
            "returnValue": true,
            "volume": 30,
            "soundOutput": "tv_speaker"
        }
        """
        
        let decoder = JSONDecoder()
        let data = json.data(using: .utf8)!
        let payload = try decoder.decode(WebOSResponsePayload.self, from: data)
        
        #expect(payload.returnValue == true)
        #expect(payload.additionalData["volume"]?.value as? Int == 30)
        #expect(payload.additionalData["soundOutput"]?.value as? String == "tv_speaker")
    }
    
    // MARK: - AnyCodable Tests
    
    @Test("AnyCodable encodes and decodes string")
    func anyCodableString() throws {
        let original = AnyCodable("test string")
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(AnyCodable.self, from: data)
        
        #expect(decoded.value as? String == "test string")
    }
    
    @Test("AnyCodable encodes and decodes integer")
    func anyCodableInteger() throws {
        let original = AnyCodable(42)
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(AnyCodable.self, from: data)
        
        #expect(decoded.value as? Int == 42)
    }
    
    @Test("AnyCodable encodes and decodes boolean")
    func anyCodableBoolean() throws {
        let original = AnyCodable(true)
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(AnyCodable.self, from: data)
        
        #expect(decoded.value as? Bool == true)
    }
    
    @Test("AnyCodable encodes and decodes double")
    func anyCodableDouble() throws {
        let original = AnyCodable(3.14)
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(AnyCodable.self, from: data)
        
        #expect((decoded.value as? Double ?? 0).isApproximatelyEqual(to: 3.14))
    }
    
    @Test("AnyCodable encodes and decodes array")
    func anyCodableArray() throws {
        let original = AnyCodable([1, 2, 3])
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(AnyCodable.self, from: data)
        
        let array = decoded.value as? [Any]
        #expect(array?.count == 3)
    }
    
    @Test("AnyCodable encodes and decodes dictionary")
    func anyCodableDictionary() throws {
        let original = AnyCodable(["key": "value"])
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(AnyCodable.self, from: data)
        
        let dict = decoded.value as? [String: Any]
        #expect(dict?["key"] as? String == "value")
    }
    
    @Test("AnyCodable encodes and decodes null")
    func anyCodableNull() throws {
        let json = "null"
        let data = json.data(using: .utf8)!
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(AnyCodable.self, from: data)
        
        #expect(decoded.value == nil)
    }
}

// MARK: - Test Helpers

private extension Double {
    func isApproximatelyEqual(to other: Double, tolerance: Double = 0.0001) -> Bool {
        abs(self - other) < tolerance
    }
}
