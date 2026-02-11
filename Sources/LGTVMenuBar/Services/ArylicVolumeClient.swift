#if LOCAL_ARYLIC_BUILD

import Foundation

// MARK: - ArylicError

/// Errors that can occur during Arylic API communication.
public enum ArylicError: Error, Equatable, LocalizedError {
    case connectionFailed(String)
    case invalidResponse(String)
    case requestFailed(Int)
    
    public var errorDescription: String? {
        switch self {
        case .connectionFailed(let message):
            return "Connection to Arylic device failed: \(message)"
        case .invalidResponse(let message):
            return "Invalid response from Arylic device: \(message)"
        case .requestFailed(let statusCode):
            return "Arylic API request failed with status code \(statusCode)"
        }
    }
}

// MARK: - ArylicVolumeClient

/// HTTP client for communicating with Arylic audio device volume control API.
public final class ArylicVolumeClient: ArylicVolumeClientProtocol, Sendable {
    private let settings: ArylicSettings
    private let session: URLSession
    
    // MARK: - Initialization
    
    /// Creates a new Arylic volume client.
    ///
    /// - Parameters:
    ///   - settings: Arylic device connection settings
    ///   - session: URLSession to use for requests (defaults to .shared)
    public init(settings: ArylicSettings, session: URLSession = .shared) {
        self.settings = settings
        self.session = session
    }
    
    // MARK: - ArylicVolumeClientProtocol
    
    public func getPlayerStatus() async throws -> (volume: Int, isMuted: Bool) {
        let response = try await performRequest(command: "getPlayerStatus")
        return try parsePlayerStatus(from: response)
    }
    
    public func volumeUp() async throws {
        _ = try await performRequest(command: "setPlayerCmd:vol++")
    }
    
    public func volumeDown() async throws {
        _ = try await performRequest(command: "setPlayerCmd:vol--")
    }
    
    public func setVolume(_ volume: Int) async throws {
        _ = try await performRequest(command: "setPlayerCmd:vol:\(volume)")
    }
    
    public func setMute(_ muted: Bool) async throws {
        let muteValue = muted ? "1" : "0"
        _ = try await performRequest(command: "setPlayerCmd:mute:\(muteValue)")
    }
    
    // MARK: - Private Methods
    
    private func performRequest(command: String) async throws -> Data {
        let url = try buildURL(command: command)
        
        let request: URLRequest = {
            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            req.timeoutInterval = settings.timeout
            return req
        }()
        
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ArylicError.connectionFailed(error.localizedDescription)
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ArylicError.invalidResponse("Not an HTTP response")
        }
        
        guard httpResponse.statusCode == 200 else {
            throw ArylicError.requestFailed(httpResponse.statusCode)
        }
        
        return data
    }
    
    private func buildURL(command: String) throws -> URL {
        // URL-encode the command parameter
        // Remove + from allowed characters since it needs to be encoded as %2B
        var allowedCharacters = CharacterSet.urlQueryAllowed
        allowedCharacters.remove(charactersIn: "+")
        
        guard let encodedCommand = command.addingPercentEncoding(withAllowedCharacters: allowedCharacters) else {
            throw ArylicError.invalidResponse("Failed to encode command")
        }
        
        let urlString = "http://\(settings.host):\(settings.port)/httpapi.asp?command=\(encodedCommand)"
        
        guard let url = URL(string: urlString) else {
            throw ArylicError.invalidResponse("Failed to construct URL")
        }
        
        return url
    }
    
    private func parsePlayerStatus(from data: Data) throws -> (volume: Int, isMuted: Bool) {
        guard let xmlString = String(data: data, encoding: .utf8) else {
            throw ArylicError.invalidResponse("Failed to decode response as UTF-8")
        }
        
        // Parse <vol> element
        guard let volumeValue = extractXMLValue(from: xmlString, tag: "vol"),
              let volume = Int(volumeValue) else {
            throw ArylicError.invalidResponse("Missing or invalid <vol> element")
        }
        
        // Parse <mute> element
        guard let muteValue = extractXMLValue(from: xmlString, tag: "mute"),
              let muteInt = Int(muteValue) else {
            throw ArylicError.invalidResponse("Missing or invalid <mute> element")
        }
        
        let isMuted = muteInt != 0
        
        return (volume: volume, isMuted: isMuted)
    }
    
    private func extractXMLValue(from xml: String, tag: String) -> String? {
        let openTag = "<\(tag)>"
        let closeTag = "</\(tag)>"
        
        guard let startRange = xml.range(of: openTag),
              let endRange = xml.range(of: closeTag),
              startRange.upperBound < endRange.lowerBound else {
            return nil
        }
        
        return String(xml[startRange.upperBound..<endRange.lowerBound])
    }
}

#endif
