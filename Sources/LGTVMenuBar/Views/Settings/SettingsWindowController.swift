import AppKit
import SwiftUI

/// The Settings window: one toolbar pane per area, like other Mac apps.
///
/// AppKit hosts it because the app has no SwiftUI scene to attach a `Settings` scene to that can
/// be opened reliably from a status item; `NSTabViewController` with the toolbar style gives the
/// standard look, pane switching and keyboard navigation.
@MainActor
final class SettingsWindowController: NSWindowController {
    enum Pane: String, CaseIterable {
        case tv, automation, display, panelCare, general, advanced, arylic

        var title: String {
            switch self {
            case .tv: return "TV"
            case .automation: return "Automation"
            case .display: return "Display"
            case .panelCare: return "Panel Care"
            case .general: return "General"
            case .advanced: return "Advanced"
            case .arylic: return "Arylic"
            }
        }

        var symbolName: String {
            switch self {
            case .tv: return "tv"
            case .automation: return "clock.arrow.2.circlepath"
            case .display: return "lock.display"
            case .panelCare: return "sparkles.tv"
            case .general: return "gearshape"
            case .advanced: return "wrench.and.screwdriver"
            case .arylic: return "hifispeaker"
            }
        }

        var height: CGFloat {
            switch self {
            case .tv: return 580
            case .automation: return 600
            case .display: return 700
            case .panelCare: return 460
            case .general: return 520
            case .advanced: return 700
            case .arylic: return 420
            }
        }
    }

    static let paneWidth: CGFloat = 560
    private static let selectedPaneKey = "settingsSelectedPane"

    private let tabController = SettingsTabViewController()

    init(controller: TVController, displayLock: DisplayLockController, softwareUpdates: SoftwareUpdateController?) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Self.paneWidth, height: Pane.tv.height),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true
        )
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        super.init(window: window)

        tabController.tabStyle = .toolbar
        var panes: [Pane] = [.tv, .automation, .display, .panelCare, .general, .advanced]
        #if LOCAL_ARYLIC_BUILD
        panes.append(.arylic)
        #endif

        for pane in panes {
            let content: AnyView
            switch pane {
            case .tv: content = AnyView(TVSettingsPane(controller: controller))
            case .automation: content = AnyView(AutomationSettingsPane(controller: controller))
            case .display: content = AnyView(DisplaySettingsPane(controller: controller, displayLock: displayLock))
            case .panelCare: content = AnyView(PanelCareSettingsPane(controller: controller))
            case .general: content = AnyView(GeneralSettingsPane(controller: controller, softwareUpdates: softwareUpdates))
            case .advanced: content = AnyView(AdvancedSettingsPane(controller: controller))
            case .arylic:
                #if LOCAL_ARYLIC_BUILD
                content = AnyView(ArylicSettingsPane(controller: controller))
                #else
                content = AnyView(EmptyView())
                #endif
            }

            let size = NSSize(width: Self.paneWidth, height: pane.height)
            let host = NSHostingController(rootView: content.frame(width: size.width, height: size.height))
            host.preferredContentSize = size
            // The pane sizes itself; without this the hosting controller fights the window resize.
            host.sizingOptions = []

            let item = NSTabViewItem(viewController: host)
            item.identifier = pane.rawValue
            item.label = pane.title
            item.image = NSImage(systemSymbolName: pane.symbolName, accessibilityDescription: pane.title)
            tabController.addTabViewItem(item)
        }

        tabController.onSelect = { identifier in
            UserDefaults.standard.set(identifier, forKey: Self.selectedPaneKey)
        }

        window.contentViewController = tabController
        select(Pane(rawValue: UserDefaults.standard.string(forKey: Self.selectedPaneKey) ?? "") ?? .tv)
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("SettingsWindowController is created in code")
    }

    func show(pane: Pane? = nil) {
        if let pane {
            select(pane)
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func select(_ pane: Pane) {
        guard let index = tabController.tabViewItems.firstIndex(where: { ($0.identifier as? String) == pane.rawValue }) else { return }
        tabController.selectedTabViewItemIndex = index
        tabController.syncWindow(animated: false)
    }
}

/// Resizes the window to the selected pane and titles it after the pane.
private final class SettingsTabViewController: NSTabViewController {
    var onSelect: ((String) -> Void)?

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        syncWindow(animated: true)
        if let identifier = tabViewItem?.identifier as? String {
            onSelect?(identifier)
        }
    }

    func syncWindow(animated: Bool) {
        guard selectedTabViewItemIndex >= 0, selectedTabViewItemIndex < tabViewItems.count else { return }
        let item = tabViewItems[selectedTabViewItemIndex]
        guard let window = view.window ?? item.viewController?.view.window,
              let size = item.viewController?.preferredContentSize, size != .zero else { return }

        window.title = item.label
        let contentRect = window.contentRect(forFrameRect: window.frame)
        guard contentRect.size != size else { return }

        // Keep the title bar where it is and grow or shrink downwards.
        var newContentRect = contentRect
        newContentRect.origin.y += contentRect.height - size.height
        newContentRect.size = size
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        window.setFrame(window.frameRect(forContentRect: newContentRect), display: true, animate: animated && !reduceMotion)
    }
}
