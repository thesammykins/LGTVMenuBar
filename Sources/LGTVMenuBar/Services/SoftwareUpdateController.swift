import Foundation

#if !UX_TESTING_APP
import Sparkle
#endif

final class SoftwareUpdateController {
    #if !UX_TESTING_APP
    private let updaterController: SPUStandardUpdaterController?
    #else
    private let updaterController: Never? = nil
    #endif

    @MainActor
    init(startingUpdater: Bool = true) {
        #if UX_TESTING_APP
        #else
        guard Self.hasRequiredBundleConfiguration else {
            updaterController = nil
            return
        }

        updaterController = SPUStandardUpdaterController(
            startingUpdater: startingUpdater,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        #endif
    }

    @MainActor
    var isEnabled: Bool {
        #if UX_TESTING_APP
        return false
        #else
        updaterController != nil
        #endif
    }

    @MainActor
    var canCheckForUpdates: Bool {
        #if UX_TESTING_APP
        return false
        #else
        updaterController?.updater.canCheckForUpdates ?? false
        #endif
    }

    @MainActor
    var automaticallyChecksForUpdates: Bool {
        get {
            #if UX_TESTING_APP
            return false
            #else
            updaterController?.updater.automaticallyChecksForUpdates ?? false
            #endif
        }
        set {
            #if UX_TESTING_APP
            _ = newValue
            #else
            updaterController?.updater.automaticallyChecksForUpdates = newValue
            #endif
        }
    }

    @MainActor
    var lastUpdateCheckDate: Date? {
        #if UX_TESTING_APP
        return nil
        #else
        updaterController?.updater.lastUpdateCheckDate
        #endif
    }

    @MainActor
    func checkForUpdates() {
        #if UX_TESTING_APP
        #else
        updaterController?.checkForUpdates(nil)
        #endif
    }

    #if !UX_TESTING_APP
    private static var hasRequiredBundleConfiguration: Bool {
        guard
            let feedURL = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
            let publicKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        else {
            return false
        }

        return !feedURL.isEmpty && !publicKey.isEmpty
    }
    #endif
}
