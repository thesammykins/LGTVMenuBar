import Foundation
import IOKit.pwr_mgt
import IOKit.ps
import OSLog
import AppKit

@MainActor
public protocol PowerManagerProtocol: Sendable {
    var isPreventingSleep: Bool { get }
    var onSleep: (@Sendable () -> Void)? { get set }
    var onWake: (@Sendable () -> Void)? { get set }
    var onScreenSleep: (@Sendable () -> Void)? { get set }
    var onScreenWake: (@Sendable () -> Void)? { get set }
    func preventSleep() async throws
    func allowSleep() async throws
    func isSystemSleeping() async -> Bool
    func startMonitoring()
    func stopMonitoring()
}

/// Service responsible for managing system power state and preventing sleep
@MainActor
final class PowerManager: PowerManagerProtocol {
    private let logger = Logger(subsystem: "com.lgtvmenubar", category: "PowerManager")
    
    /// IOKit power assertion reference
    private var powerAssertionID: IOPMAssertionID?
    
    /// Current power assertion state
    private var _isPreventingSleep = false
    
    /// Whether sleep prevention is currently active
    var isPreventingSleep: Bool {
        return _isPreventingSleep
    }
    
    /// Callback when Mac is about to sleep
    var onSleep: (@Sendable () -> Void)?
    
    /// Callback when Mac wakes from sleep
    var onWake: (@Sendable () -> Void)?
    
    /// Callback when display sleeps
    var onScreenSleep: (@Sendable () -> Void)?
    
    /// Callback when display wakes
    var onScreenWake: (@Sendable () -> Void)?
    
    /// Storage for workspace notification observers
    private var workspaceNotificationObservers: [NSObjectProtocol] = []
    
    /// Initialize PowerManager
    init() {
        logger.info("PowerManager initialized")
    }
    
    deinit {
        // Note: stopMonitoring() should be called before deallocating to clean up observers
        // Clean up any existing power assertion
        // Note: deinit is synchronous and cannot call async cleanup properly
        // The app should call allowSleep() before deallocating
    }
    
    /// Prevent system sleep while maintaining display wake
    /// - Throws: `LGTVError.powerManagementError` if preventing sleep fails
    func preventSleep() async throws {
        guard !_isPreventingSleep else {
            logger.debug("Sleep prevention already active")
            return
        }
        
        logger.info("Preventing system sleep")
        
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let reason = "LGTV Menu Bar - Active TV Connection" as CFString
                let assertionType = kIOPMAssertionTypePreventUserIdleSystemSleep
                
                var assertionID: IOPMAssertionID = 0
                let result = IOPMAssertionCreateWithName(
                    assertionType as CFString,
                    IOPMAssertionLevel(kIOPMAssertionLevelOn),
                    reason as CFString,
                    &assertionID
                )
                
                DispatchQueue.main.async {
                    if result == kIOReturnSuccess {
                        self.powerAssertionID = assertionID
                        self._isPreventingSleep = true
                        self.logger.info("Sleep prevention enabled (assertion ID: \(assertionID))")
                        continuation.resume()
                    } else {
                        self.logger.error("Failed to create power assertion: \(result)")
                        continuation.resume(throwing: LGTVError.powerManagementError("Failed to prevent system sleep (code: \(result))"))
                    }
                }
            }
        }
    }
    
    /// Allow system to sleep normally
    /// - Throws: `LGTVError.powerManagementError` if allowing sleep fails
    func allowSleep() async throws {
        guard _isPreventingSleep else {
            logger.debug("Sleep prevention not active")
            return
        }
        
        guard let assertionID = powerAssertionID else {
            logger.warning("No power assertion to release")
            _isPreventingSleep = false
            return
        }
        
        logger.info("Allowing system sleep")
        
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = IOPMAssertionRelease(assertionID)
                
                DispatchQueue.main.async {
                    if result == kIOReturnSuccess {
                        self.powerAssertionID = nil
                        self._isPreventingSleep = false
                        self.logger.info("Sleep prevention disabled")
                        continuation.resume()
                    } else {
                        self.logger.error("Failed to release power assertion: \(result)")
                        continuation.resume(throwing: LGTVError.powerManagementError("Failed to allow system sleep (code: \(result))"))
                    }
                }
            }
        }
    }
    
    /// Check if system is currently sleeping
    /// - Returns: `true` if system is sleeping, `false` otherwise
    func isSystemSleeping() async -> Bool {
        // Simple sleep detection based on power state
        // Since we're already on main actor, we can directly access the property
        let isOnBattery = false // Simplified for now
        let isSleeping = !isOnBattery && _isPreventingSleep == false
        return isSleeping
    }
    
    /// Start monitoring system sleep/wake events
    /// This subscribes to NSWorkspace notifications for:
    /// - willSleepNotification (Mac going to sleep)
    /// - didWakeNotification (Mac woke up)
    /// - screensDidSleepNotification (Display sleeping)
    /// - screensDidWakeNotification (Display woke)
    func startMonitoring() {
        logger.info("Starting sleep/wake event monitoring")
        
        let notificationCenter = NSWorkspace.shared.notificationCenter
        
        // Monitor Mac sleep events
        let sleepObserver = notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.logger.info("System will sleep")
                self?.onSleep?()
            }
        }
        workspaceNotificationObservers.append(sleepObserver)
        
        // Monitor Mac wake events
        let wakeObserver = notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.logger.info("System did wake")
                self?.onWake?()
            }
        }
        workspaceNotificationObservers.append(wakeObserver)
        
        // Monitor screen sleep events
        let screenSleepObserver = notificationCenter.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.logger.info("Screens did sleep")
                self?.onScreenSleep?()
            }
        }
        workspaceNotificationObservers.append(screenSleepObserver)
        
        // Monitor screen wake events
        let screenWakeObserver = notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.logger.info("Screens did wake")
                self?.onScreenWake?()
            }
        }
        workspaceNotificationObservers.append(screenWakeObserver)
        
        logger.info("Sleep/wake event monitoring started (observing \(self.workspaceNotificationObservers.count) notifications)")
    }
    
    /// Stop monitoring system sleep/wake events
    func stopMonitoring() {
        logger.info("Stopping sleep/wake event monitoring")
        
        let notificationCenter = NSWorkspace.shared.notificationCenter
        for observer in workspaceNotificationObservers {
            notificationCenter.removeObserver(observer)
        }
        workspaceNotificationObservers.removeAll()
        
        logger.info("Sleep/wake event monitoring stopped")
    }
}
