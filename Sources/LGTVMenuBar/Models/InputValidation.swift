import Foundation

/// Validation for values typed into settings. Each returns nil when the value is acceptable, or
/// a sentence to show under the field.
public enum InputValidation {
    public static func tvName(_ value: String) -> String? {
        value.trimmingCharacters(in: .whitespaces).isEmpty ? "Enter a name for the TV." : nil
    }

    /// IPv4 address or host name. The TV is always addressed on the local network.
    public static func host(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "Enter the TV's IP address." }

        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        if parts.count == 4, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) {
            return parts.allSatisfy({ (Int($0) ?? 256) <= 255 }) ? nil : "Each part of an IP address is between 0 and 255."
        }
        if trimmed.allSatisfy({ $0.isNumber || $0 == "." }) {
            return "An IP address has four numbers, like 192.168.1.20."
        }

        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-."))
        guard trimmed.unicodeScalars.allSatisfy(allowed.contains), !trimmed.hasPrefix("-"), !trimmed.hasPrefix(".") else {
            return "Use an IP address like 192.168.1.20 or a host name."
        }
        return nil
    }

    public static func optionalHost(_ value: String) -> String? {
        value.trimmingCharacters(in: .whitespaces).isEmpty ? nil : host(value)
    }

    public static func macAddress(_ value: String) -> String? {
        let hex = value.filter(\.isHexDigit)
        let separators = value.filter { !$0.isHexDigit }
        guard hex.count == 12, separators.allSatisfy({ $0 == ":" || $0 == "-" || $0 == " " }) else {
            return "A MAC address has 12 hexadecimal digits, like AA:BB:CC:DD:EE:FF."
        }
        return nil
    }

    /// Normalises a valid MAC address to upper-case, colon-separated form.
    public static func normalizedMACAddress(_ value: String) -> String {
        let hex = Array(value.filter(\.isHexDigit).uppercased())
        guard hex.count == 12 else { return value }
        return stride(from: 0, to: 12, by: 2).map { String(hex[$0...$0 + 1]) }.joined(separator: ":")
    }

    public static func optionalPort(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return nil }
        guard let port = Int(trimmed), (1...65_535).contains(port) else {
            return "A port is a number from 1 to 65535."
        }
        return nil
    }

    public static func optionalSeconds(_ value: String, range: ClosedRange<Double>) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return nil }
        guard let seconds = Double(trimmed), range.contains(seconds) else {
            return "Enter a number of seconds from \(Int(range.lowerBound)) to \(Int(range.upperBound))."
        }
        return nil
    }
}
