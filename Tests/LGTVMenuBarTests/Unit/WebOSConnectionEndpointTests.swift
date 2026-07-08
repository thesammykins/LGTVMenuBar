import Foundation
import Testing
@testable import LGTVMenuBar

@Suite("WebOS Connection Endpoint Tests")
struct WebOSConnectionEndpointTests {
    @Test("preferred connection order tries secure WebSocket first")
    func preferredOrderTriesSecureFirst() {
        #expect(WebOSConnectionEndpoint.preferredOrder == [.secure, .insecure])
    }

    @Test("secure endpoint uses wss on port 3001")
    func secureEndpoint() {
        let endpoint = WebOSConnectionEndpoint.secure

        #expect(endpoint.scheme == "wss")
        #expect(endpoint.port == 3001)
        #expect(endpoint.usesSSL)
        #expect(endpoint.url(for: "192.168.1.100")?.absoluteString == "wss://192.168.1.100:3001/")
    }

    @Test("insecure endpoint uses ws on port 3000")
    func insecureEndpoint() {
        let endpoint = WebOSConnectionEndpoint.insecure

        #expect(endpoint.scheme == "ws")
        #expect(endpoint.port == 3000)
        #expect(!endpoint.usesSSL)
        #expect(endpoint.url(for: "192.168.1.100")?.absoluteString == "ws://192.168.1.100:3000/")
    }
}
