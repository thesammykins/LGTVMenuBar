import Testing
@testable import LGTVMenuBar

@Suite("ConnectionState Tests")
struct ConnectionStateTests {
    
    // MARK: - Basic State Tests
    
    @Test("disconnected state is equatable")
    func disconnectedEquatable() {
        let state1 = ConnectionState.disconnected
        let state2 = ConnectionState.disconnected
        #expect(state1 == state2)
    }
    
    @Test("connecting state is equatable")
    func connectingEquatable() {
        let state1 = ConnectionState.connecting
        let state2 = ConnectionState.connecting
        #expect(state1 == state2)
    }
    
    @Test("registering state is equatable")
    func registeringEquatable() {
        let state1 = ConnectionState.registering
        let state2 = ConnectionState.registering
        #expect(state1 == state2)
    }
    
    @Test("connected state is equatable")
    func connectedEquatable() {
        let state1 = ConnectionState.connected
        let state2 = ConnectionState.connected
        #expect(state1 == state2)
    }
    
    // MARK: - Error State Tests
    
    @Test("error state contains error")
    func errorStateContainsError() {
        let testError = TestError.sample
        let state = ConnectionState.error(testError)
        
        if case .error(let error) = state {
            #expect(error is TestError)
        } else {
            Issue.record("Expected error state")
        }
    }
    
    @Test("different states are not equal")
    func differentStatesNotEqual() {
        #expect(ConnectionState.disconnected != ConnectionState.connecting)
        #expect(ConnectionState.connecting != ConnectionState.registering)
        #expect(ConnectionState.registering != ConnectionState.connected)
    }
    
    // MARK: - State Properties Tests
    
    @Test("isConnected returns true only for connected state")
    func isConnectedProperty() {
        #expect(ConnectionState.disconnected.isConnected == false)
        #expect(ConnectionState.connecting.isConnected == false)
        #expect(ConnectionState.registering.isConnected == false)
        #expect(ConnectionState.connected.isConnected == true)
        #expect(ConnectionState.error(TestError.sample).isConnected == false)
    }
    
    @Test("isDisconnected returns true only for disconnected state")
    func isDisconnectedProperty() {
        #expect(ConnectionState.disconnected.isDisconnected == true)
        #expect(ConnectionState.connecting.isDisconnected == false)
        #expect(ConnectionState.registering.isDisconnected == false)
        #expect(ConnectionState.connected.isDisconnected == false)
        #expect(ConnectionState.error(TestError.sample).isDisconnected == false)
    }
    
    @Test("isTransitioning returns true for connecting and registering")
    func isTransitioningProperty() {
        #expect(ConnectionState.disconnected.isTransitioning == false)
        #expect(ConnectionState.connecting.isTransitioning == true)
        #expect(ConnectionState.registering.isTransitioning == true)
        #expect(ConnectionState.connected.isTransitioning == false)
        #expect(ConnectionState.error(TestError.sample).isTransitioning == false)
    }
    
    @Test("hasError returns true only for error state")
    func hasErrorProperty() {
        #expect(ConnectionState.disconnected.hasError == false)
        #expect(ConnectionState.connecting.hasError == false)
        #expect(ConnectionState.registering.hasError == false)
        #expect(ConnectionState.connected.hasError == false)
        #expect(ConnectionState.error(TestError.sample).hasError == true)
    }
}

// MARK: - Test Helpers

private enum TestError: Error {
    case sample
}
