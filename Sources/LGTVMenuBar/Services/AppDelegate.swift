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
    private var controller: TVController!
    private var eventMonitors: [Any] = []
    
    private let logger = Logger(subsystem: "com.lgtvmenubar", category: "AppDelegate")
    
    // MARK: - Application Lifecycle
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize controller
        controller = TVController()
        
        // Set activation policy to hide dock icon (menu bar only)
        NSApp.setActivationPolicy(.accessory)
        
        // Set up status bar item
        setupStatusItem()
        
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
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // Clean up event monitors
        for monitor in eventMonitors {
            NSEvent.removeMonitor(monitor)
        }
        eventMonitors.removeAll()
        
        logger.info("Application terminating")
    }
    
    // MARK: - Status Item Setup
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        guard let button = statusItem?.button else {
            logger.error("\("Failed to create status bar button", privacy: .public)")
            return
        }
        
        // Set icon
        button.image = NSImage(systemSymbolName: "tv", accessibilityDescription: "LGTV Menu Bar")
        
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
        let contentView = MenuBarView(controller: controller)
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
        
        logger.debug("Popover shown")
    }
    
    private func hidePopover() {
        popover?.performClose(nil)
        logger.debug("Popover hidden")
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
