import AppKit
import SwiftUI
import OSLog

/// AppDelegate managing menu bar status item and custom NSPopover
/// Replaces MenuBarExtra to prevent unwanted auto-dismiss behavior
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    
    // MARK: - Properties
    
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var settingsWindow: NSWindow?
    private var uxTestingWindow: NSWindow?
    private var controller: TVController!
    private let softwareUpdates = SoftwareUpdateController()
    private var eventMonitors: [Any] = []
    
    private let logger = Logger(subsystem: "com.lgtvmenubar", category: "AppDelegate")
    
    // MARK: - Application Lifecycle
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize controller
        controller = TVController()

        #if UX_TESTING_APP
        controller.applyUXTestingFixture()
        NSApp.setActivationPolicy(.regular)
        showUXTestingWindow()

        logger.info("\("UX testing window launched successfully", privacy: .public)")
        return
        #else
        
        // Set activation policy to hide dock icon (menu bar only)
        NSApp.setActivationPolicy(.accessory)
        
        // Set up status bar item
        setupStatusItem()

        controller.connectionStateDidChange = { [weak self] state in
            guard let statusItem = self?.statusItem else { return }
            StatusItemIconManager.updateStatusItem(statusItem, for: state)
        }
        
        // Set up popover with custom behavior
        setupPopover()
        
        // Set up event monitors for dismiss handling
        setupEventMonitors()
        
        // Check if onboarding is needed
        checkOnboardingStatus()
        
        // Auto-connect if enabled and configuration exists (not during onboarding)
        if controller.configuration != nil {
            let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
            if hasCompletedOnboarding {
                Task {
                    // Small delay to let the app fully initialize
                    try? await Task.sleep(for: .milliseconds(500))
                    await controller.autoConnectOnStartup()
                }
            }
        }
        
        logger.info("\("Application launched successfully", privacy: .public)")
        #endif
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // Clean up event monitors
        for monitor in eventMonitors {
            NSEvent.removeMonitor(monitor)
        }
        eventMonitors.removeAll()
        
        logger.info("Application terminating")
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        #if UX_TESTING_APP
        return
        #else
        guard let controller = controller else { return }
        controller.refreshMediaKeyCapture()

        if popover?.isShown == true {
            return
        }

        guard controller.connectionState.isDisconnected || controller.connectionState.hasError else {
            return
        }

        Task {
            await controller.ensureTVAwake(reason: "appActivated")
        }
        #endif
    }
    
    // MARK: - Status Item Setup
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        guard let button = statusItem?.button else {
            logger.error("\("Failed to create status bar button", privacy: .public)")
            return
        }
        
        // Set icon
        if let statusItem {
            StatusItemIconManager.updateStatusItem(statusItem, for: controller.connectionState)
        }
        
        // Set action
        button.action = #selector(togglePopover)
        button.target = self
        
        logger.info("Status bar item configured")
    }
    
    // MARK: - Popover Setup
    
    private func setupPopover() {
        popover = NSPopover()
        
        guard let popover = popover else {
            logger.error("Failed to create popover")
            return
        }
        
        // KEY: Use .applicationDefined to prevent auto-dismiss on interactions
        popover.behavior = .applicationDefined
        popover.animates = true
        
        // Create hosting controller with MenuBarView
        let contentView = MenuBarView(controller: controller, softwareUpdates: softwareUpdates) { [weak self] in
            Task { @MainActor in
                self?.hidePopover()
                self?.showSettingsWindow()
            }
        }
            .environment(\.dismissPopover, DismissPopoverAction { [weak self] in
                Task { @MainActor in
                    self?.hidePopover()
                }
            })
        
        let hostingController = NSHostingController(rootView: contentView)
        popover.contentViewController = hostingController
        
        logger.info("Popover configured with applicationDefined behavior")
    }
    
    // MARK: - Event Monitors
    
    private func setupEventMonitors() {
        // Monitor escape key for dismiss
        let escapeKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.popover?.isShown == true else {
                return event
            }
            
            // Escape key code is 53
            if event.keyCode == 53 {
                self.hidePopover()
                return nil // Consume the event
            }
            
            return event
        }
        
        if let monitor = escapeKeyMonitor {
            eventMonitors.append(monitor)
        }
        
        // Monitor clicks outside popover for dismiss
        let clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self = self, let popover = self.popover, popover.isShown else {
                return
            }
            
            // Get click location in screen coordinates
            let clickLocation = NSEvent.mouseLocation
            
            // Get popover window frame
            guard let popoverWindow = popover.contentViewController?.view.window else {
                return
            }
            
            let popoverFrame = popoverWindow.frame
            
            // If click is outside popover, dismiss it
            if !popoverFrame.contains(clickLocation) {
                self.hidePopover()
            }
        }
        
        if let monitor = clickOutsideMonitor {
            eventMonitors.append(monitor)
        }
        
        logger.info("Event monitors configured")
    }
    
    // MARK: - Popover Actions
    
    @objc private func togglePopover() {
        guard let popover = popover else { return }
        
        if popover.isShown {
            hidePopover()
        } else {
            showPopover()
        }
    }
    
    private func showPopover() {
        guard let button = statusItem?.button, let popover = popover else {
            return
        }
        
        // Show popover relative to status bar button
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        
        // CRITICAL: Make popover window key and activate app for proper focus
        // This ensures buttons, toggles, pickers work correctly
        popover.contentViewController?.view.window?.makeKey()
        NSApp.activate(ignoringOtherApps: true)

        if controller.configuration != nil {
            Task {
                await controller.ensureTVAwake(reason: "menuOpened")
            }
        }
        
        logger.debug("Popover shown")
    }
    
    private func hidePopover() {
        popover?.performClose(nil)
        logger.debug("Popover hidden")
    }

    private func showSettingsWindow() {
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView(controller: controller, softwareUpdates: softwareUpdates)
        let hostingController = NSHostingController(rootView: settingsView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.center()
        window.setContentSize(NSSize(width: 480, height: 440))
        window.isReleasedWhenClosed = false

        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    // MARK: - Onboarding
    
    private func checkOnboardingStatus() {
        let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        let hasConfiguration = controller.configuration != nil
        
        // Show onboarding if not completed and no configuration exists
        if !hasCompletedOnboarding && !hasConfiguration {
            logger.info("First run detected, showing onboarding")
            showOnboarding()
        } else {
            logger.info("Onboarding already completed")
        }
    }
    
    private func showOnboarding() {
        let onboardingView = OnboardingView(controller: controller) { [weak self] in
            self?.logger.info("Onboarding completed")
        }
        
        let hostingController = NSHostingController(rootView: onboardingView)
        
        // Create window for onboarding
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Welcome to LGTV Menu Bar"
        window.styleMask = [.titled, .closable]
        window.center()
        window.setContentSize(NSSize(width: 500, height: 600))
        window.isReleasedWhenClosed = false
        window.level = .floating
        
        // Show window modally
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        logger.info("Onboarding window displayed")
    }

    #if UX_TESTING_APP
    private func showUXTestingWindow() {
        let rootView = UXTestingRootView(controller: controller)
        let hostingController = NSHostingController(rootView: rootView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "LGTV Menu Bar UX Validation"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.center()
        window.setContentSize(NSSize(width: 980, height: 720))
        window.minSize = NSSize(width: 820, height: 560)
        window.isReleasedWhenClosed = false

        uxTestingWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    #endif
}

// MARK: - Environment Key for Dismiss Action

/// Environment key for dismissing popover from SwiftUI views
private struct DismissPopoverKey: EnvironmentKey {
    static let defaultValue: DismissPopoverAction = DismissPopoverAction {}
}

extension EnvironmentValues {
    var dismissPopover: DismissPopoverAction {
        get { self[DismissPopoverKey.self] }
        set { self[DismissPopoverKey.self] = newValue }
    }
}

/// Action to dismiss the popover
struct DismissPopoverAction: Sendable {
    private let action: @Sendable () -> Void
    
    init(_ action: @escaping @Sendable () -> Void) {
        self.action = action
    }
    
    func callAsFunction() {
        action()
    }
}
