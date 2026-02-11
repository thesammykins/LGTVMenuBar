import Foundation

/// Protocol for interacting with Arylic audio device volume control API.
///
/// Arylic devices expose an HTTP API at `http://{host}:{port}/httpapi.asp?command={cmd}`
/// for controlling playback and volume.
public protocol ArylicVolumeClientProtocol: Sendable {
    /// Retrieves the current player status including volume and mute state.
    ///
    /// - Returns: A tuple containing the current volume (0-100) and mute state
    /// - Throws: Network or parsing errors
    func getPlayerStatus() async throws -> (volume: Int, isMuted: Bool)
    
    /// Increases the volume by one step.
    ///
    /// - Throws: Network errors
    func volumeUp() async throws
    
    /// Decreases the volume by one step.
    ///
    /// - Throws: Network errors
    func volumeDown() async throws
    
    /// Sets the volume to a specific level.
    ///
    /// - Parameter volume: Target volume level (0-100)
    /// - Throws: Network errors
    func setVolume(_ volume: Int) async throws
    
    /// Sets the mute state.
    ///
    /// - Parameter muted: `true` to mute, `false` to unmute
    /// - Throws: Network errors
    func setMute(_ muted: Bool) async throws
}
