import Testing
import Foundation
@testable import LGTVMenuBar

@Suite("LGTVError Tests")
struct LGTVErrorTests {
    
    // MARK: - Error Creation Tests
    
    @Test("connectionFailed creates error with message")
    func connectionFailedCreation() {
        let error = LGTVError.connectionFailed("timeout")
        if case .connectionFailed(let message) = error {
            #expect(message == "timeout")
        } else {
            Issue.record("Expected connectionFailed error")
        }
    }
    
    @Test("commandFailed creates error with message")
    func commandFailedCreation() {
        let error = LGTVError.commandFailed("invalid command")
        if case .commandFailed(let message) = error {
            #expect(message == "invalid command")
        } else {
            Issue.record("Expected commandFailed error")
        }
    }
    
    @Test("networkError wraps underlying error")
    func networkErrorWrapsError() {
        let underlyingError = URLError(.notConnectedToInternet)
        let error = LGTVError.networkError(underlyingError)
        
        if case .networkError(let wrapped) = error {
            #expect(wrapped is URLError)
        } else {
            Issue.record("Expected networkError")
        }
    }
    
    // MARK: - LocalizedError Tests
    
    @Test("connectionFailed provides localized description")
    func connectionFailedLocalizedDescription() {
        let error = LGTVError.connectionFailed("Connection refused")
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription!.contains("Connection refused"))
    }
    
    @Test("pairingRejected provides localized description")
    func pairingRejectedLocalizedDescription() {
        let error = LGTVError.pairingRejected
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription!.lowercased().contains("pairing") || 
                error.errorDescription!.lowercased().contains("rejected"))
    }
    
    @Test("pairingTimeout provides localized description")
    func pairingTimeoutLocalizedDescription() {
        let error = LGTVError.pairingTimeout
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription!.lowercased().contains("pairing") || 
                error.errorDescription!.lowercased().contains("timeout"))
    }
    
    @Test("commandFailed provides localized description")
    func commandFailedLocalizedDescription() {
        let error = LGTVError.commandFailed("Volume command failed")
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription!.contains("Volume command failed"))
    }
    
    @Test("invalidResponse provides localized description")
    func invalidResponseLocalizedDescription() {
        let error = LGTVError.invalidResponse
        #expect(error.errorDescription != nil)
    }
    
    @Test("tvNotFound provides localized description")
    func tvNotFoundLocalizedDescription() {
        let error = LGTVError.tvNotFound
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription!.lowercased().contains("tv") || 
                error.errorDescription!.lowercased().contains("found"))
    }
    
    @Test("networkError provides localized description with underlying error")
    func networkErrorLocalizedDescription() {
        let underlyingError = URLError(.notConnectedToInternet)
        let error = LGTVError.networkError(underlyingError)
        #expect(error.errorDescription != nil)
    }
    
    @Test("wakeFailed provides localized description")
    func wakeFailedLocalizedDescription() {
        let error = LGTVError.wakeFailed
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription!.lowercased().contains("wake"))
    }
    
    // MARK: - Equatable Tests (for cases without associated values)
    
    @Test("simple error cases are equatable")
    func simpleErrorsEquatable() {
        #expect(LGTVError.pairingRejected == LGTVError.pairingRejected)
        #expect(LGTVError.pairingTimeout == LGTVError.pairingTimeout)
        #expect(LGTVError.invalidResponse == LGTVError.invalidResponse)
        #expect(LGTVError.tvNotFound == LGTVError.tvNotFound)
        #expect(LGTVError.wakeFailed == LGTVError.wakeFailed)
    }
    
    @Test("connectionFailed errors with same message are equal")
    func connectionFailedEquatable() {
        let error1 = LGTVError.connectionFailed("timeout")
        let error2 = LGTVError.connectionFailed("timeout")
        #expect(error1 == error2)
    }
    
    @Test("connectionFailed errors with different messages are not equal")
    func connectionFailedNotEqual() {
        let error1 = LGTVError.connectionFailed("timeout")
        let error2 = LGTVError.connectionFailed("refused")
        #expect(error1 != error2)
    }
    
    @Test("commandFailed errors with same message are equal")
    func commandFailedEquatable() {
        let error1 = LGTVError.commandFailed("invalid")
        let error2 = LGTVError.commandFailed("invalid")
        #expect(error1 == error2)
    }
    
    // MARK: - Error as Error Protocol
    
    @Test("LGTVError conforms to Error protocol")
    func conformsToErrorProtocol() {
        let error: any Error = LGTVError.tvNotFound
        #expect(error is LGTVError)
    }
    
    @Test("LGTVError conforms to LocalizedError protocol")
    func conformsToLocalizedErrorProtocol() {
        let error: any LocalizedError = LGTVError.tvNotFound
        #expect(error.errorDescription != nil)
    }
}
