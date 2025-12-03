import Foundation
import CoreAudio
import OSLog

/// Represents the type of audio output currently active
public enum AudioOutputType: Equatable, Sendable {
    case builtInSpeakers
    case hdmi          // HDMI or DisplayPort audio
    case externalDevice // USB audio, headphones, etc.
    case unknown
    
    /// Whether this output type supports granular volume control with a slider
    /// eARC/HDMI outputs typically don't report accurate volume levels
    public var supportsVolumeSlider: Bool {
        switch self {
        case .builtInSpeakers:
            return true
        case .hdmi, .externalDevice, .unknown:
            return false
        }
    }
}

/// Protocol for audio output detection
@MainActor
public protocol AudioOutputServiceProtocol: Sendable {
    var currentOutputType: AudioOutputType { get }
    var currentOutputName: String { get }
    func startMonitoring(callback: @escaping @Sendable (AudioOutputType) -> Void)
    func stopMonitoring()
}

/// Service to detect and monitor the current audio output device
@MainActor
public final class AudioOutputService: AudioOutputServiceProtocol, @unchecked Sendable {
    private nonisolated let logger = Logger(subsystem: "com.lgtvmenubar", category: "AudioOutputService")
    
    private var _currentOutputType: AudioOutputType = .unknown
    private var _currentOutputName: String = ""
    private var outputChangeCallback: (@Sendable (AudioOutputType) -> Void)?
    private var listenerBlock: AudioObjectPropertyListenerBlock?
    
    public var currentOutputType: AudioOutputType {
        return _currentOutputType
    }
    
    public var currentOutputName: String {
        return _currentOutputName
    }
    
    public init() {
        // Initial detection
        detectCurrentOutput()
    }
    
    /// Start monitoring for audio output changes
    public func startMonitoring(callback: @escaping @Sendable (AudioOutputType) -> Void) {
        self.outputChangeCallback = callback
        
        // Set up listener for default output device changes
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in
                self?.detectCurrentOutput()
                if let outputType = self?._currentOutputType {
                    self?.outputChangeCallback?(outputType)
                }
            }
        }
        
        self.listenerBlock = block
        
        let result = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            block
        )
        
        if result != noErr {
            logger.error("Failed to add audio output listener: \(result)")
        } else {
            logger.info("Started monitoring audio output changes")
        }
    }
    
    /// Stop monitoring for audio output changes
    public func stopMonitoring() {
        guard let block = listenerBlock else { return }
        
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            block
        )
        
        listenerBlock = nil
        outputChangeCallback = nil
        logger.info("Stopped monitoring audio output changes")
    }
    
    /// Detect the current default audio output device
    private func detectCurrentOutput() {
        let deviceID = getDefaultOutputDeviceID()
        guard deviceID != kAudioObjectUnknown else {
            _currentOutputType = .unknown
            _currentOutputName = "Unknown"
            return
        }
        
        let name = getDeviceName(deviceID: deviceID)
        let uid = getDeviceUID(deviceID: deviceID)
        
        _currentOutputName = name
        _currentOutputType = classifyDevice(name: name, uid: uid)
        
        logger.info("Current audio output: \(name) (\(uid)) -> \(String(describing: self._currentOutputType))")
    }
    
    /// Get the default output device ID
    private nonisolated func getDefaultOutputDeviceID() -> AudioDeviceID {
        var deviceID: AudioDeviceID = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let result = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        
        if result != noErr {
            logger.error("Failed to get default output device: \(result)")
            return kAudioObjectUnknown
        }
        
        return deviceID
    }
    
    /// Get the name of an audio device
    private nonisolated func getDeviceName(deviceID: AudioDeviceID) -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var size = UInt32(MemoryLayout<CFString?>.size)
        var name: CFString?
        
        let result = withUnsafeMutablePointer(to: &name) { ptr in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, ptr)
        }
        
        if result != noErr {
            return "Unknown"
        }
        
        return (name as String?) ?? "Unknown"
    }
    
    /// Get the UID of an audio device
    private nonisolated func getDeviceUID(deviceID: AudioDeviceID) -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var size = UInt32(MemoryLayout<CFString?>.size)
        var uid: CFString?
        
        let result = withUnsafeMutablePointer(to: &uid) { ptr in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, ptr)
        }
        
        if result != noErr {
            return ""
        }
        
        return (uid as String?) ?? ""
    }
    
    /// Classify a device based on its name and UID
    private nonisolated func classifyDevice(name: String, uid: String) -> AudioOutputType {
        let lowerName = name.lowercased()
        let lowerUID = uid.lowercased()
        
        // Check for built-in speakers
        if lowerName.contains("built-in") || lowerName.contains("macbook") || 
           lowerName.contains("internal") || lowerUID.contains("applehda") && !lowerUID.contains("dp") {
            return .builtInSpeakers
        }
        
        // Check for HDMI/DisplayPort/eARC output
        if lowerName.contains("hdmi") || lowerName.contains("displayport") || 
           lowerName.contains("dp") || lowerUID.contains("outputdp") ||
           lowerName.contains("lg") || lowerName.contains("tv") ||
           lowerName.contains("earc") || lowerName.contains("arc") {
            return .hdmi
        }
        
        // Check UID patterns for HDMI
        if lowerUID.contains("dp:") || lowerUID.contains("hdmi") {
            return .hdmi
        }
        
        // Everything else is external (USB, Bluetooth, headphones, etc.)
        return .externalDevice
    }
    
    deinit {
        // Note: Must call stopMonitoring() before dealloc from MainActor context
    }
}
