import SwiftUI

/// Main application entry point
/// Uses AppDelegate to manage custom NSPopover instead of MenuBarExtra
/// to prevent unwanted auto-dismiss behavior on user interactions
@main
struct LGTVMenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    
    var body: some Scene {
        // Empty scene - all UI is managed through AppDelegate's NSPopover
        WindowGroup {
            EmptyView()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 0, height: 0)
    }
}
