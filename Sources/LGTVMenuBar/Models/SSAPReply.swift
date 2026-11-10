import Foundation

/// Payload of a confirmed SSAP reply.
///
/// `@unchecked Sendable`: the dictionary is produced by `JSONSerialization` and never mutated, so
/// it only holds immutable Foundation value objects. Avoiding a full typed JSON model keeps the
/// many loosely specified webOS payloads readable at the call site.
public struct SSAPReply: @unchecked Sendable {
    public let payload: [String: Any]

    public init(payload: [String: Any] = [:]) {
        self.payload = payload
    }

    public func string(_ key: String) -> String? { payload[key] as? String }
    public func bool(_ key: String) -> Bool? { payload[key] as? Bool }
    public func dictionary(_ key: String) -> [String: Any]? { payload[key] as? [String: Any] }

    /// Compact, key-sorted JSON for diagnostics.
    public var jsonString: String {
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            return String(describing: payload)
        }
        return string
    }
}
