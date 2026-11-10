import AppKit
import CoreGraphics
import Foundation

/// A display attached to this Mac, as far as Display Lock cares.
public struct DisplayInfo: Equatable, Sendable, Identifiable {
    public let displayID: UInt32
    public let uuid: String
    public let name: String
    public let vendorID: UInt32
    public let isBuiltIn: Bool
    public let currentMode: DisplayModeSpec?
    public let hdrSupported: Bool
    public let hdrEnabled: Bool

    public init(displayID: UInt32, uuid: String, name: String, vendorID: UInt32, isBuiltIn: Bool, currentMode: DisplayModeSpec?, hdrSupported: Bool, hdrEnabled: Bool) {
        self.displayID = displayID
        self.uuid = uuid
        self.name = name
        self.vendorID = vendorID
        self.isBuiltIn = isBuiltIn
        self.currentMode = currentMode
        self.hdrSupported = hdrSupported
        self.hdrEnabled = hdrEnabled
    }

    public var id: String { uuid }

    /// EDID manufacturer "GSM" (LG Electronics / Goldstar).
    public static let lgVendorID: UInt32 = 0x1E6D

    public var isLG: Bool { vendorID == Self.lgVendorID }
}

public enum DisplayServiceError: Error, Equatable, LocalizedError {
    case displayNotFound
    case modeNotAvailable(String)
    case configurationFailed(Int32)
    case hdrControlUnavailable

    public var errorDescription: String? {
        switch self {
        case .displayNotFound:
            return "The TV is not connected to this Mac as a display."
        case .modeNotAvailable(let mode):
            return "macOS does not offer \(mode) on this display right now."
        case .configurationFailed(let code):
            return "macOS refused the display mode change (code \(code))."
        case .hdrControlUnavailable:
            return "This version of macOS does not let apps switch HDR."
        }
    }
}

@MainActor
public protocol DisplayServiceProtocol {
    func displays() -> [DisplayInfo]
    func availableModes(forDisplayUUID uuid: String) -> [DisplayModeSpec]
    func setMode(_ mode: DisplayModeSpec, displayUUID: String) throws
    /// False when macOS offers no way for this app to switch HDR.
    var canControlHDR: Bool { get }
    func setHDR(_ enabled: Bool, displayUUID: String) throws
}

/// CoreGraphics-backed display control.
///
/// Resolution and refresh rate use public API. macOS has no public API for switching HDR, so
/// that part resolves SkyLight symbols at run time. If Apple removes or renames them the lookup
/// fails, `canControlHDR` turns false and the rest of the app is unaffected; nothing links
/// against the private framework.
@MainActor
public final class DisplayService: DisplayServiceProtocol {
    private typealias HDRQuery = @convention(c) (UInt32) -> Bool
    // Called with two trailing zero arguments: observed builds take either two or four
    // parameters, and on both Mac architectures surplus register arguments are ignored.
    private typealias HDRSetter = @convention(c) (UInt32, Bool, Int32, Int32) -> Int32

    private let hdrSupportedQuery: HDRQuery?
    private let hdrEnabledQuery: HDRQuery?
    private let hdrSetter: HDRSetter?

    public init() {
        let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)

        func symbol<T>(_ name: String, as type: T.Type) -> T? {
            guard let handle, let pointer = dlsym(handle, name) else { return nil }
            return unsafeBitCast(pointer, to: type)
        }

        hdrSupportedQuery = symbol("SLSDisplaySupportsHDRMode", as: HDRQuery.self)
        hdrEnabledQuery = symbol("SLSDisplayIsHDRModeEnabled", as: HDRQuery.self)
        hdrSetter = symbol("SLSDisplaySetHDRModeEnabled", as: HDRSetter.self)
    }

    public var canControlHDR: Bool {
        hdrSupportedQuery != nil && hdrEnabledQuery != nil && hdrSetter != nil
    }

    public func displays() -> [DisplayInfo] {
        onlineDisplayIDs().compactMap { displayID in
            guard let uuid = Self.uuid(for: displayID) else { return nil }
            return DisplayInfo(
                displayID: displayID,
                uuid: uuid,
                name: Self.name(for: displayID),
                vendorID: CGDisplayVendorNumber(displayID),
                isBuiltIn: CGDisplayIsBuiltin(displayID) != 0,
                currentMode: CGDisplayCopyDisplayMode(displayID).map(Self.spec),
                hdrSupported: hdrSupportedQuery?(displayID) ?? false,
                hdrEnabled: hdrEnabledQuery?(displayID) ?? false
            )
        }
    }

    public func availableModes(forDisplayUUID uuid: String) -> [DisplayModeSpec] {
        guard let displayID = displayID(forUUID: uuid) else { return [] }
        var seen = Set<DisplayModeSpec>()
        return allModes(for: displayID)
            .map(Self.spec)
            .filter { seen.insert($0).inserted }
            .sorted {
                if $0.pointWidth != $1.pointWidth { return $0.pointWidth > $1.pointWidth }
                if $0.pointHeight != $1.pointHeight { return $0.pointHeight > $1.pointHeight }
                if $0.isHiDPI != $1.isHiDPI { return $0.isHiDPI }
                return $0.refreshRate > $1.refreshRate
            }
    }

    public func setMode(_ mode: DisplayModeSpec, displayUUID: String) throws {
        guard let displayID = displayID(forUUID: displayUUID) else {
            throw DisplayServiceError.displayNotFound
        }
        guard let target = allModes(for: displayID).first(where: { Self.spec($0).matches(mode) }) else {
            throw DisplayServiceError.modeNotAvailable(mode.displayName)
        }

        var configuration: CGDisplayConfigRef?
        var result = CGBeginDisplayConfiguration(&configuration)
        guard result == .success, let configuration else {
            throw DisplayServiceError.configurationFailed(result.rawValue)
        }
        result = CGConfigureDisplayWithDisplayMode(configuration, displayID, target, nil)
        guard result == .success else {
            CGCancelDisplayConfiguration(configuration)
            throw DisplayServiceError.configurationFailed(result.rawValue)
        }
        // Permanent, like a change made in System Settings, so it survives logout.
        result = CGCompleteDisplayConfiguration(configuration, .permanently)
        guard result == .success else {
            throw DisplayServiceError.configurationFailed(result.rawValue)
        }
    }

    public func setHDR(_ enabled: Bool, displayUUID: String) throws {
        guard let hdrSetter, canControlHDR else {
            throw DisplayServiceError.hdrControlUnavailable
        }
        guard let displayID = displayID(forUUID: displayUUID) else {
            throw DisplayServiceError.displayNotFound
        }
        // The return value is not trusted: the symbol is undocumented and its return type is a
        // guess. Display Lock reads the state back a few seconds later and judges by that.
        _ = hdrSetter(displayID, enabled, 0, 0)
    }

    // MARK: - Private

    private func onlineDisplayIDs() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }

    private func displayID(forUUID uuid: String) -> CGDirectDisplayID? {
        onlineDisplayIDs().first { Self.uuid(for: $0) == uuid }
    }

    private func allModes(for displayID: CGDirectDisplayID) -> [CGDisplayMode] {
        let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        let modes = (CGDisplayCopyAllDisplayModes(displayID, options) as? [CGDisplayMode]) ?? []
        return modes.filter { $0.isUsableForDesktopGUI() }
    }

    private static func uuid(for displayID: CGDirectDisplayID) -> String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String?
    }

    private static func name(for displayID: CGDirectDisplayID) -> String {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        let screen = NSScreen.screens.first { ($0.deviceDescription[key] as? NSNumber)?.uint32Value == displayID }
        return screen?.localizedName ?? "Display \(displayID)"
    }

    private static func spec(_ mode: CGDisplayMode) -> DisplayModeSpec {
        DisplayModeSpec(
            pixelWidth: mode.pixelWidth,
            pixelHeight: mode.pixelHeight,
            pointWidth: mode.width,
            pointHeight: mode.height,
            refreshRate: mode.refreshRate
        )
    }
}
