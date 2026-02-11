#if LOCAL_ARYLIC_BUILD

import Foundation
@testable import LGTVMenuBar

/// Mock implementation of ArylicVolumeClientProtocol for testing.
public final class MockArylicVolumeClient: ArylicVolumeClientProtocol, Sendable {
    // MARK: - Recorded Calls
    
    public struct Call: Equatable, Sendable {
        public enum Method: Equatable, Sendable {
            case getPlayerStatus
            case volumeUp
            case volumeDown
            case setVolume(Int)
            case setMute(Bool)
        }
        
        public let method: Method
        public let timestamp: Date
        
        public init(method: Method, timestamp: Date = Date()) {
            self.method = method
            self.timestamp = timestamp
        }
    }
    
    private let calls: SendableBox<[Call]>
    
    // MARK: - Configurable Returns
    
    private let getPlayerStatusResult: SendableBox<Result<(volume: Int, isMuted: Bool), Error>?>
    private let volumeUpResult: SendableBox<Result<Void, Error>?>
    private let volumeDownResult: SendableBox<Result<Void, Error>?>
    private let setVolumeResult: SendableBox<Result<Void, Error>?>
    private let setMuteResult: SendableBox<Result<Void, Error>?>
    
    // MARK: - Initialization
    
    public init() {
        self.calls = SendableBox([])
        self.getPlayerStatusResult = SendableBox(nil)
        self.volumeUpResult = SendableBox(nil)
        self.volumeDownResult = SendableBox(nil)
        self.setVolumeResult = SendableBox(nil)
        self.setMuteResult = SendableBox(nil)
    }
    
    // MARK: - Configuration
    
    public func setGetPlayerStatusResult(_ result: Result<(volume: Int, isMuted: Bool), Error>) {
        getPlayerStatusResult.value = result
    }
    
    public func setVolumeUpResult(_ result: Result<Void, Error>) {
        volumeUpResult.value = result
    }
    
    public func setVolumeDownResult(_ result: Result<Void, Error>) {
        volumeDownResult.value = result
    }
    
    public func setSetVolumeResult(_ result: Result<Void, Error>) {
        setVolumeResult.value = result
    }
    
    public func setSetMuteResult(_ result: Result<Void, Error>) {
        setMuteResult.value = result
    }
    
    // MARK: - Call Inspection
    
    public var recordedCalls: [Call] {
        calls.value
    }
    
    public func reset() {
        calls.value.removeAll()
        getPlayerStatusResult.value = nil
        volumeUpResult.value = nil
        volumeDownResult.value = nil
        setVolumeResult.value = nil
        setMuteResult.value = nil
    }
    
    // MARK: - ArylicVolumeClientProtocol
    
    public func getPlayerStatus() async throws -> (volume: Int, isMuted: Bool) {
        calls.value.append(Call(method: .getPlayerStatus))
        
        guard let result = getPlayerStatusResult.value else {
            return (volume: 50, isMuted: false)
        }
        
        return try result.get()
    }
    
    public func volumeUp() async throws {
        calls.value.append(Call(method: .volumeUp))
        
        if let result = volumeUpResult.value {
            _ = try result.get()
        }
    }
    
    public func volumeDown() async throws {
        calls.value.append(Call(method: .volumeDown))
        
        if let result = volumeDownResult.value {
            _ = try result.get()
        }
    }
    
    public func setVolume(_ volume: Int) async throws {
        calls.value.append(Call(method: .setVolume(volume)))
        
        if let result = setVolumeResult.value {
            _ = try result.get()
        }
    }
    
    public func setMute(_ muted: Bool) async throws {
        calls.value.append(Call(method: .setMute(muted)))
        
        if let result = setMuteResult.value {
            _ = try result.get()
        }
    }
}

// MARK: - SendableBox

/// Thread-safe box for mutable state in Sendable types.
private final class SendableBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: T
    
    var value: T {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _value
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _value = newValue
        }
    }
    
    init(_ value: T) {
        self._value = value
    }
}

#endif
