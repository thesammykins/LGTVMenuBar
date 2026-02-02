import Foundation

/// WebOS commands that can be sent to the TV
public enum WebOSCommand: Sendable {
    case getForegroundAppInfo
    case getCurrentForegroundAppInfo  // One-time query without subscription
    case getInputList
    case powerOn
    case powerOff
    case volumeUp
    case volumeDown
    case setVolume(Int)
    case getVolume
    case subscribeVolume
    case getSoundOutput
    case subscribeSoundOutput
    case setSoundOutput(String)
    case mute
    case unmute
    case setInput(String)
    case screenOn
    case screenOff
    case setDeviceInfo(inputId: String, icon: String, label: String)
}