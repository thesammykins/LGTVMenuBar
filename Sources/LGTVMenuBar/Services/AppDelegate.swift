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
    private var settingsWindowController: SettingsWindowController?
    private var onboardingWindow: NSWindow?
    private var uxTestingWindow: NSWindow?
    private var controller: TVController!
    private var displayLock: DisplayLockController!
    private let softwareUpdates = SoftwareUpdateController()
    private var eventMonitors: [Any] = []
    
    private let logger = Logger(subsystem: "com.lgtvmenubar", category: "AppDelegate")
    
    // MARK: - Application Lifecycle
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize controller
        controller = TVController()
        displayLock = DisplayLockController(tv: controller, displayService: DisplayService())
        displayLock.log = { [weak self] level, message, metadata in
            self?.controller.diagnosticLogger.log(level: level, category: "DisplayLock", message: message, metadata: metadata)
        }

        #if UX_TESTING_APP
        controller.applyUXTestingFixture()
        NSApp.setActivationPolicy(.regular)
        if let directory = ProcessInfo.processInfo.environment["LGTV_UX_SNAPSHOT_DIR"] {
            UXSnapshotRenderer(controller: controller, displayLock: displayLock).renderAll(to: URL(fileURLWithPath: directory))
            NSApp.terminate(nil)
            return
        }
        showUXTestingWindow()

        logger.info("\("UX testing window launched successfully", privacy: .public)")
        return
        #else
        
        // Set activation policy to hide dock icon (menu bar only)
        NSApp.setActivationPolicy(.accessory)
        
        // Set up status bar item
        setupStatusItem()

        setupMainMenu()

        controller.connectionStateDidChange = { [weak self] state in
            self?.displayLock.noteChange("connection")
            guard let statusItem = self?.statusItem else { return }
            StatusItemIconManager.updateStatusItem(statusItem, for: state)
        }
        controller.foregroundDidChange = { [weak self] _ in
            self?.displayLock.noteChange("foreground")
        }
        controller.configurationDidChange = { [weak self] _ in
            self?.displayLock.profileDidChange()
        }
        displayLock.startObservingDisplays()
        
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

        controller.handleAutomationTrigger(.appActivated)
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
        
        // Left click shows the popover; right click (or Control-click) shows a short menu.
        button.action = #selector(statusItemClicked)
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        
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
        let contentView = MenuBarView(controller: controller, displayLock: displayLock) { [weak self] pane in
            self?.hidePopover()
            self?.showSettingsWindow(pane: pane)
        }
        
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
    
    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        let isSecondaryClick = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        if isSecondaryClick {
            hidePopover()
            showStatusMenu()
        } else {
            togglePopover()
        }
    }

    private func showStatusMenu() {
        guard let statusItem else { return }
        let menu = NSMenu()
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        if softwareUpdates.isEnabled {
            menu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "").target = self
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit LGTV Menu Bar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // Attaching the menu only for this click keeps left click free for the popover.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openSettings() {
        showSettingsWindow(pane: nil)
    }

    @objc private func checkForUpdates() {
        softwareUpdates.checkForUpdates()
    }

    /// An accessory app has no menu bar of its own, but text fields still rely on the Edit menu
    /// for Cut, Copy and Paste, and Settings on the standard Command-comma.
    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit LGTV Menu Bar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)

        NSApp.mainMenu = mainMenu
    }

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
        NSApp.activate()

        controller.handleAutomationTrigger(.menuOpened)
        
        logger.debug("Popover shown")
    }
    
    private func hidePopover() {
        popover?.performClose(nil)
        logger.debug("Popover hidden")
    }

    private func showSettingsWindow(pane: SettingsWindowController.Pane?) {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(
                controller: controller,
                displayLock: displayLock,
                softwareUpdates: softwareUpdates
            )
        }
        settingsWindowController?.show(pane: pane)
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
            self?.onboardingWindow?.close()
            self?.onboardingWindow = nil
        }
        
        let hostingController = NSHostingController(rootView: onboardingView)
        
        // Create window for onboarding
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Welcome to LGTV Menu Bar"
        window.styleMask = [.titled, .closable]
        window.center()
        window.setContentSize(NSSize(width: 500, height: 600))
        window.isReleasedWhenClosed = false
        onboardingWindow = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        
        logger.info("Onboarding window displayed")
    }

    #if UX_TESTING_APP
    private func showUXTestingWindow() {
        let rootView = UXTestingRootView(controller: controller, displayLock: displayLock)
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
        NSApp.activate()
    }
    #endif
}
