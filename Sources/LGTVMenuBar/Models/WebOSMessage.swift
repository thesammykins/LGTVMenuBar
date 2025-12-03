import Foundation

// MARK: - WebOS Request

/// Request message sent to WebOS TV
public struct WebOSRequest: Codable, Sendable {
    public let id: String
    public let type: String
    public let uri: String
    public let payload: [String: AnyCodable]?
    
    public init(id: String, type: String, uri: String, payload: [String: AnyCodable]? = nil) {
        self.id = id
        self.type = type
        self.uri = uri
        self.payload = payload
    }
}

// MARK: - WebOS Response

/// Response message received from WebOS TV
public struct WebOSResponse: Codable, Sendable {
    public let id: String
    public let type: String
    public let payload: WebOSResponsePayload
    
    public init(id: String, type: String, payload: WebOSResponsePayload) {
        self.id = id
        self.type = type
        self.payload = payload
    }
}

/// Payload contained in WebOS response
public struct WebOSResponsePayload: Codable, Sendable {
    public let returnValue: Bool
    public var additionalData: [String: AnyCodable] = [:]
    
    public init(returnValue: Bool, additionalData: [String: AnyCodable] = [:]) {
        self.returnValue = returnValue
        self.additionalData = additionalData
    }
    
    // Custom coding to handle dynamic keys
    private struct CodingKeys: CodingKey {
        var stringValue: String
        var intValue: Int?
        
        init?(stringValue: String) {
            self.stringValue = stringValue
            self.intValue = nil
        }
        
        init?(intValue: Int) {
            self.stringValue = String(intValue)
            self.intValue = intValue
        }
        
        static let returnValue = CodingKeys(stringValue: "returnValue")!
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.returnValue = try container.decode(Bool.self, forKey: .returnValue)
        
        // Decode remaining keys as additional data
        var additionalData: [String: AnyCodable] = [:]
        for key in container.allKeys where key.stringValue != "returnValue" {
            let value = try container.decode(AnyCodable.self, forKey: key)
            additionalData[key.stringValue] = value
        }
        self.additionalData = additionalData
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(returnValue, forKey: .returnValue)
        
        for (key, value) in additionalData {
            if let codingKey = CodingKeys(stringValue: key) {
                try container.encode(value, forKey: codingKey)
            }
        }
    }
}

// MARK: - AnyCodable

/// Type-erased Codable wrapper for handling dynamic JSON values
public struct AnyCodable: Codable, Sendable, Equatable {
    private enum StoredValue: Equatable {
        case null
        case bool(Bool)
        case int(Int)
        case double(Double)
        case string(String)
        case array([AnyCodable])
        case dictionary([String: AnyCodable])
    }
    
    private let stored: StoredValue
    
    public var value: Any? {
        switch stored {
        case .null: return nil
        case .bool(let v): return v
        case .int(let v): return v
        case .double(let v): return v
        case .string(let v): return v
        case .array(let v): return v.map { $0.value }
        case .dictionary(let v): return v.mapValues { $0.value }
        }
    }
    
    public init(_ value: Any?) {
        switch value {
        case nil:
            stored = .null
        case let bool as Bool:
            stored = .bool(bool)
        case let int as Int:
            stored = .int(int)
        case let double as Double:
            stored = .double(double)
        case let string as String:
            stored = .string(string)
        case let array as [Any]:
            stored = .array(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            stored = .dictionary(dict.mapValues { AnyCodable($0) })
        default:
            stored = .null
        }
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if container.decodeNil() {
            stored = .null
        } else if let bool = try? container.decode(Bool.self) {
            stored = .bool(bool)
        } else if let int = try? container.decode(Int.self) {
            stored = .int(int)
        } else if let double = try? container.decode(Double.self) {
            stored = .double(double)
        } else if let string = try? container.decode(String.self) {
            stored = .string(string)
        } else if let array = try? container.decode([AnyCodable].self) {
            stored = .array(array)
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            stored = .dictionary(dict)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unable to decode value"
            )
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch stored {
        case .null:
            try container.encodeNil()
        case .bool(let v):
            try container.encode(v)
        case .int(let v):
            try container.encode(v)
        case .double(let v):
            try container.encode(v)
        case .string(let v):
            try container.encode(v)
        case .array(let v):
            try container.encode(v)
        case .dictionary(let v):
            try container.encode(v)
        }
    }
}
