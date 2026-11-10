#if UX_TESTING_APP
import AppKit
import SwiftUI

/// Renders the menu and every Settings pane to PNG files, in each state worth looking at.
///
/// Drawing happens inside the app, so it needs neither Screen Recording nor Accessibility
/// permission and can run from a script or an agent's shell.
@MainActor
struct UXSnapshotRenderer {
    let controller: TVController
    let displayLock: DisplayLockController

    func renderAll(to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let suffix = appearance == .darkAqua ? "dark" : "light"

            for scenario in TVController.UXScenario.allCases {
                controller.applyUXTestingFixture(scenario)
                render(MenuBarView(controller: controller, displayLock: displayLock).background(Color(nsColor: .windowBackgroundColor)), width: 300, height: nil, appearance: appearance, to: directory.appendingPathComponent("menu-\(scenario.rawValue)-\(suffix).png"))
            }

            controller.applyUXTestingFixture(.rooted)
            let panes: [(SettingsWindowController.Pane, AnyView)] = [
                (.tv, AnyView(TVSettingsPane(controller: controller))),
                (.automation, AnyView(AutomationSettingsPane(controller: controller))),
                (.display, AnyView(DisplaySettingsPane(controller: controller, displayLock: displayLock))),
                (.panelCare, AnyView(PanelCareSettingsPane(controller: controller))),
                (.general, AnyView(GeneralSettingsPane(controller: controller, softwareUpdates: nil))),
                (.advanced, AnyView(AdvancedSettingsPane(controller: controller)))
            ]
            for (pane, view) in panes {
                render(view, width: SettingsWindowController.paneWidth, height: pane.height, appearance: appearance, to: directory.appendingPathComponent("settings-\(pane.rawValue)-\(suffix).png"))
            }

            controller.applyUXTestingFixture(.automationPaused)
            render(AutomationSettingsPane(controller: controller), width: SettingsWindowController.paneWidth, height: SettingsWindowController.Pane.automation.height, appearance: appearance, to: directory.appendingPathComponent("settings-automation-paused-\(suffix).png"))

            controller.applyUXTestingFixture(.noTV)
            render(TVSettingsPane(controller: controller), width: SettingsWindowController.paneWidth, height: SettingsWindowController.Pane.tv.height, appearance: appearance, to: directory.appendingPathComponent("settings-tv-empty-\(suffix).png"))
        }
    }

    private func render<Content: View>(_ view: Content, width: CGFloat, height: CGFloat?, appearance: NSAppearance.Name, to url: URL) {
        let hosting = NSHostingView(rootView: view.frame(width: width, height: height))
        hosting.layoutSubtreeIfNeeded()
        let size = NSSize(width: width, height: height ?? ceil(hosting.fittingSize.height) + 2)

        // Controls only draw fully inside a window; this one is never shown.
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = hosting
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        // Let SwiftUI run its first update pass (onAppear, tasks) before drawing.
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        hosting.layoutSubtreeIfNeeded()

        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
    }
}
#endif
