#if LOCAL_ARYLIC_BUILD

import Foundation
import Testing
@testable import LGTVMenuBar

// MARK: - MockURLProtocol

/// Mock URLProtocol for intercepting HTTP requests in tests.
final class MockURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var _requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _requestHandler
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _requestHandler = newValue
        }
    }
    
    override class func canInit(with request: URLRequest) -> Bool {
        true
    }
    
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }
    
    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            fatalError("Handler is not set")
        }
        
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    
    override func stopLoading() {}
}

// MARK: - Thread-safe Request Capture

final class RequestCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var _request: URLRequest?
    
    var request: URLRequest? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _request
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _request = newValue
        }
    }
}

// MARK: - ArylicVolumeClientTests

@Suite("ArylicVolumeClient Tests", .serialized)
struct ArylicVolumeClientTests {
    
    // MARK: - URL Construction Tests
    
    @Test("URL construction for getPlayerStatus")
    func testGetPlayerStatusURLConstruction() async throws {
        let settings = ArylicSettings(host: "192.168.1.100", port: 80, timeout: 5.0)
        let capture = RequestCapture()
        
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        
        MockURLProtocol.requestHandler = { request in
            capture.request = request
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let data = "<vol>50</vol><mute>0</mute>".data(using: .utf8)!
            return (response, data)
        }
        
        let client = ArylicVolumeClient(settings: settings, session: session)
        _ = try await client.getPlayerStatus()
        
        #expect(capture.request?.url?.absoluteString == "http://192.168.1.100:80/httpapi.asp?command=getPlayerStatus")
        #expect(capture.request?.httpMethod == "GET")
    }
    
    @Test("URL encoding for volumeUp command with ++ characters")
    func testVolumeUpURLEncoding() async throws {
        let settings = ArylicSettings(host: "192.168.1.100", port: 80, timeout: 5.0)
        let capture = RequestCapture()
        
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        
        MockURLProtocol.requestHandler = { request in
            capture.request = request
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }
        
        let client = ArylicVolumeClient(settings: settings, session: session)
        try await client.volumeUp()
        
        // Verify that vol++ is URL-encoded as vol%2B%2B
        let urlString = capture.request?.url?.absoluteString ?? ""
        #expect(urlString.contains("vol%2B%2B"))
        #expect(urlString == "http://192.168.1.100:80/httpapi.asp?command=setPlayerCmd:vol%2B%2B")
    }
    
    @Test("URL encoding for volumeDown command with -- characters")
    func testVolumeDownURLEncoding() async throws {
        let settings = ArylicSettings(host: "192.168.1.100", port: 80, timeout: 5.0)
        let capture = RequestCapture()
        
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        
        MockURLProtocol.requestHandler = { request in
            capture.request = request
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }
        
        let client = ArylicVolumeClient(settings: settings, session: session)
        try await client.volumeDown()
        
        let urlString = capture.request?.url?.absoluteString ?? ""
        #expect(urlString == "http://192.168.1.100:80/httpapi.asp?command=setPlayerCmd:vol--")
    }
    
    @Test("URL construction for setVolume")
    func testSetVolumeURLConstruction() async throws {
        let settings = ArylicSettings(host: "192.168.1.100", port: 80, timeout: 5.0)
        let capture = RequestCapture()
        
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        
        MockURLProtocol.requestHandler = { request in
            capture.request = request
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }
        
        let client = ArylicVolumeClient(settings: settings, session: session)
        try await client.setVolume(75)
        
        #expect(capture.request?.url?.absoluteString == "http://192.168.1.100:80/httpapi.asp?command=setPlayerCmd:vol:75")
    }
    
    @Test("URL construction for setMute with true")
    func testSetMuteTrueURLConstruction() async throws {
        let settings = ArylicSettings(host: "192.168.1.100", port: 80, timeout: 5.0)
        let capture = RequestCapture()
        
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        
        MockURLProtocol.requestHandler = { request in
            capture.request = request
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }
        
        let client = ArylicVolumeClient(settings: settings, session: session)
        try await client.setMute(true)
        
        #expect(capture.request?.url?.absoluteString == "http://192.168.1.100:80/httpapi.asp?command=setPlayerCmd:mute:1")
    }
    
    @Test("URL construction for setMute with false")
    func testSetMuteFalseURLConstruction() async throws {
        let settings = ArylicSettings(host: "192.168.1.100", port: 80, timeout: 5.0)
        let capture = RequestCapture()
        
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        
        MockURLProtocol.requestHandler = { request in
            capture.request = request
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }
        
        let client = ArylicVolumeClient(settings: settings, session: session)
        try await client.setMute(false)
        
        #expect(capture.request?.url?.absoluteString == "http://192.168.1.100:80/httpapi.asp?command=setPlayerCmd:mute:0")
    }
    
    // MARK: - Response Parsing Tests
    
    @Test("Parse valid getPlayerStatus response")
    func testParseValidPlayerStatus() async throws {
        let settings = ArylicSettings(host: "192.168.1.100", port: 80, timeout: 5.0)
        
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let xmlData = """
            <root>
                <vol>65</vol>
                <mute>1</mute>
                <other>data</other>
            </root>
            """.data(using: .utf8)!
            return (response, xmlData)
        }
        
        let client = ArylicVolumeClient(settings: settings, session: session)
        let result = try await client.getPlayerStatus()
        
        #expect(result.volume == 65)
        #expect(result.isMuted == true)
    }
    
    @Test("Parse getPlayerStatus response with mute 0")
    func testParsePlayerStatusUnmuted() async throws {
        let settings = ArylicSettings(host: "192.168.1.100", port: 80, timeout: 5.0)
        
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let xmlData = "<vol>30</vol><mute>0</mute>".data(using: .utf8)!
            return (response, xmlData)
        }
        
        let client = ArylicVolumeClient(settings: settings, session: session)
        let result = try await client.getPlayerStatus()
        
        #expect(result.volume == 30)
        #expect(result.isMuted == false)
    }
    
    @Test("Parse malformed XML missing vol element")
    func testParseMalformedXMLMissingVol() async throws {
        let settings = ArylicSettings(host: "192.168.1.100", port: 80, timeout: 5.0)
        
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let xmlData = "<mute>0</mute>".data(using: .utf8)!
            return (response, xmlData)
        }
        
        let client = ArylicVolumeClient(settings: settings, session: session)
        
        do {
            _ = try await client.getPlayerStatus()
            #expect(Bool(false), "Expected error to be thrown")
        } catch let error as ArylicError {
            #expect(error == .invalidResponse("Missing or invalid <vol> element"))
        }
    }
    
    @Test("Parse malformed XML missing mute element")
    func testParseMalformedXMLMissingMute() async throws {
        let settings = ArylicSettings(host: "192.168.1.100", port: 80, timeout: 5.0)
        
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let xmlData = "<vol>50</vol>".data(using: .utf8)!
            return (response, xmlData)
        }
        
        let client = ArylicVolumeClient(settings: settings, session: session)
        
        do {
            _ = try await client.getPlayerStatus()
            #expect(Bool(false), "Expected error to be thrown")
        } catch let error as ArylicError {
            #expect(error == .invalidResponse("Missing or invalid <mute> element"))
        }
    }
    
    @Test("Parse empty response")
    func testParseEmptyResponse() async throws {
        let settings = ArylicSettings(host: "192.168.1.100", port: 80, timeout: 5.0)
        
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }
        
        let client = ArylicVolumeClient(settings: settings, session: session)
        
        do {
            _ = try await client.getPlayerStatus()
            #expect(Bool(false), "Expected error to be thrown")
        } catch let error as ArylicError {
            #expect(error == .invalidResponse("Missing or invalid <vol> element"))
        }
    }
    
    // MARK: - Error Handling Tests
    
    @Test("Handle HTTP 404 error")
    func testHTTP404Error() async throws {
        let settings = ArylicSettings(host: "192.168.1.100", port: 80, timeout: 5.0)
        
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 404,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }
        
        let client = ArylicVolumeClient(settings: settings, session: session)
        
        do {
            _ = try await client.getPlayerStatus()
            #expect(Bool(false), "Expected error to be thrown")
        } catch let error as ArylicError {
            #expect(error == .requestFailed(404))
        }
    }
    
    @Test("Handle HTTP 500 error")
    func testHTTP500Error() async throws {
        let settings = ArylicSettings(host: "192.168.1.100", port: 80, timeout: 5.0)
        
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 500,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }
        
        let client = ArylicVolumeClient(settings: settings, session: session)
        
        do {
            try await client.volumeUp()
            #expect(Bool(false), "Expected error to be thrown")
        } catch let error as ArylicError {
            #expect(error == .requestFailed(500))
        }
    }
    
    @Test("Handle network connection failure")
    func testNetworkConnectionFailure() async throws {
        let settings = ArylicSettings(host: "192.168.1.100", port: 80, timeout: 5.0)
        
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        
        struct NetworkError: Error, LocalizedError {
            var errorDescription: String? { "Network unreachable" }
        }
        
        MockURLProtocol.requestHandler = { _ in
            throw NetworkError()
        }
        
        let client = ArylicVolumeClient(settings: settings, session: session)
        
        do {
            try await client.volumeDown()
            #expect(Bool(false), "Expected error to be thrown")
        } catch let error as ArylicError {
            if case .connectionFailed(let message) = error {
                // Just verify it's a connectionFailed error
                #expect(message.count > 0)
            } else {
                #expect(Bool(false), "Expected connectionFailed error")
            }
        }
    }
}

#endif
