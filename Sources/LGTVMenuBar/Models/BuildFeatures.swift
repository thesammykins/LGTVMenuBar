import Foundation

/// Build-time feature flags for conditional compilation.
public struct BuildFeatures {
    /// Indicates whether Arylic volume control features are available in this build.
    ///
    /// Returns `true` when built with the `LOCAL_ARYLIC_BUILD` flag.
    ///
    /// The current SwiftPM package enables this flag for default app and test builds.
    public static var isArylicAvailable: Bool {
        #if LOCAL_ARYLIC_BUILD
        return true
        #else
        return false
        #endif
    }
}
