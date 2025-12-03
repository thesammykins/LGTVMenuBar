import Foundation
import AppKit
@preconcurrency import Carbon.HIToolbox
import OSLog

@MainActor
public protocol MediaKeyManagerProtocol: Sendable {
    var isCapturingMediaKeys: Bool { get }
    var shouldCaptureMediaKeys: Bool { get set }
    var hasAccessibilityPermission: Bool { get }
    func startMediaKeyCapture(callback: @escaping @Sendable (MediaKey) -> Void) async throws
    func stopMediaKeyCapture() async throws
    func requestAccessibilityPermission() -> Bool
}

/// Service responsible for capturing media key events for TV control
@MainActor
final class MediaKeyManager: MediaKeyManagerProtocol {
    private nonisolated let logger = Logger(subsystem: "com.lgtvmenubar", category: "MediaKeyManager")
    
    /// Event tap reference for intercepting media keys
    private var eventTap: CFMachPort?
    
    /// Run loop source for the event tap
    private var runLoopSource: CFRunLoopSource?
    
    /// Current media key capture state
    private var _isCapturingMediaKeys = false
    
    /// Whether media key capture is currently active
    var isCapturingMediaKeys: Bool {
        return _isCapturingMediaKeys
    }
    
    /// Whether media keys should be captured (vs passed through to macOS)
    /// Thread-safe property for access from event tap callback
    nonisolated(unsafe) var shouldCaptureMediaKeys: Bool = true
    
    /// Check if accessibility permission is granted (without prompting)
    var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }
    
    /// Callback for media key events
    /// Thread-safe property for access from event tap callback
    private nonisolated(unsafe) var mediaKeyCallback: (@Sendable (MediaKey) -> Void)?
    
    /// Initialize MediaKeyManager
    init() {
        logger.info("MediaKeyManager initialized")
    }
    
    /// Request accessibility permission (prompts user if not granted)
    /// Returns true if permission is granted, false otherwise
    nonisolated func requestAccessibilityPermission() -> Bool {
        let optionKey = "AXTrustedCheckOptionPrompt"
        let options: [String: Any] = [optionKey: true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
    
    deinit {
        // Clean up any existing event tap
        // Note: deinit is synchronous and cannot call async cleanup properly
        // The app should call stopMediaKeyCapture() before deallocating
    }
    
    /// Start capturing media key events
    /// - Parameter callback: Closure called when media key events are detected
    /// - Throws: `LGTVError.mediaKeyError` if starting capture fails
    func startMediaKeyCapture(callback: @escaping @Sendable (MediaKey) -> Void) async throws {
        guard !_isCapturingMediaKeys else {
            logger.debug("Media key capture already active")
            return
        }
        
        logger.info("Starting media key capture")
        
        // Check accessibility permissions (don't prompt here, UI should handle that)
        guard hasAccessibilityPermission else {
            throw LGTVError.mediaKeyError("Accessibility permissions are required for media key capture. Please grant permission in System Settings > Privacy & Security > Accessibility.")
        }
        
        // Store callback
        self.mediaKeyCallback = callback
        
        // Create event tap
        // NX_SYSDEFINED has raw value 14 - this is where media keys are delivered
        let eventMask = CGEventMask(1 << 14)
        
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else {
                    return Unmanaged.passRetained(event)
                }
                
                let manager = Unmanaged<MediaKeyManager>.fromOpaque(refcon).takeUnretainedValue()
                return manager.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            throw LGTVError.mediaKeyError("Failed to create event tap for media key capture")
        }
        
        self.eventTap = eventTap
        
        // Create run loop source
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        
        self.runLoopSource = runLoopSource
        self._isCapturingMediaKeys = true
        
        logger.info("Media key capture started successfully")
    }
    
    /// Stop capturing media key events
    /// - Throws: `LGTVError.mediaKeyError` if stopping capture fails
    func stopMediaKeyCapture() async throws {
        guard _isCapturingMediaKeys else {
            logger.debug("Media key capture not active")
            return
        }
        
        logger.info("Stopping media key capture")
        
        // Remove run loop source
        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }
        
        // Disable and release event tap
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }
        
        self._isCapturingMediaKeys = false
        self.mediaKeyCallback = nil
        
        logger.info("Media key capture stopped")
    }
    
    // MARK: - Private Methods
    
    /// Handle incoming CGEvent and filter media keys
    private nonisolated func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Media keys come as NX_SYSDEFINED (type 14)
        guard type.rawValue == 14 else {
            return Unmanaged.passRetained(event)
        }
        
        // Convert to NSEvent to extract media key data
        guard let nsEvent = NSEvent(cgEvent: event) else {
            return Unmanaged.passRetained(event)
        }
        
        // Media key events have subtype 8 (screenChanged is actually used for media keys)
        guard nsEvent.subtype.rawValue == 8 else {
            return Unmanaged.passRetained(event)
        }
        
        // Extract key code and state from data1
        let data1 = nsEvent.data1
        let keyCode = (data1 & 0xFFFF0000) >> 16
        let keyState = data1 & 0xFF00
        let isKeyDown = keyState == 0x0A00
        
        // Only process key down events
        guard isKeyDown else {
            return Unmanaged.passRetained(event)
        }
        
        // Map key codes to MediaKey
        // NX_KEYTYPE_SOUND_UP = 0, NX_KEYTYPE_SOUND_DOWN = 1, NX_KEYTYPE_MUTE = 7
        let mediaKey: MediaKey?
        switch keyCode {
        case 0: mediaKey = .volumeUp
        case 1: mediaKey = .volumeDown
        case 7: mediaKey = .mute
        default: mediaKey = nil
        }
        
        guard let key = mediaKey else {
            return Unmanaged.passRetained(event)
        }
        
        // Check if we should capture
        let shouldCapture = self.shouldCaptureMediaKeys
        
        if shouldCapture {
            logger.debug("Media key captured: \(String(describing: key))")
            mediaKeyCallback?(key)
            return nil  // Consume the event
        } else {
            // Pass through to macOS
            return Unmanaged.passRetained(event)
        }
    }
    
    /// Check accessibility permissions (internal use, no prompt)
    @MainActor
    private func checkAccessibilityPermissions() -> Bool {
        return AXIsProcessTrusted()
    }
}
