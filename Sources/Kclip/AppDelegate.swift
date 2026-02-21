// AppDelegate.swift
// Kclip – Open-source keyboard-first clipboard manager
// Wires together: menu bar icon, clipboard monitoring, global hotkey, floating panel.

import AppKit
import SwiftUI
import ServiceManagement

/// Central coordinator that wires together all of Kclip's subsystems.
///
/// Responsibilities (in launch order):
/// 1. Creates the menu bar status item.
/// 2. Builds the ``FloatingPanelController``.
/// 3. Starts ``ClipboardMonitor`` and connects it to ``ClipboardStore``.
/// 4. Registers the global ⌘⇧V hotkey via ``HotkeyManager``.
/// 5. Checks for Accessibility permission and prompts if missing.
final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Core Objects

    private let store       = ClipboardStore()
    private let monitor     = ClipboardMonitor()
    private let pasteHelper = PasteHelper()
    private let hotkey      = HotkeyManager.shared

    // MARK: - UI

    private var statusItem: NSStatusItem?
    private var panelController: FloatingPanelController?

    // MARK: - App Lifecycle

    /// `true` when the process is being launched as a test host by Xcode.
    /// All heavy setup (hotkeys, clipboard monitor, UI) is skipped so the
    /// unit-test runner doesn't hang on headless CI machines.
    private var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !isRunningTests else { return }
        setupStatusBar()
        setupFloatingPanel()
        setupClipboardMonitor()
        setupHotkey()
        checkAccessibility()
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
        hotkey.unregister()
    }

    // MARK: - Setup: Status Bar

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = NSImage(
                systemSymbolName: "doc.on.clipboard",
                accessibilityDescription: "Kclip"
            )
            button.image?.isTemplate = true  // Adapts to dark/light menu bar
            button.action = #selector(statusBarButtonClicked)
            button.target = self
            // By default NSStatusBarButton only forwards left-clicks.
            // Opt in to right-click so statusBarButtonClicked receives it too.
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    
    @objc private func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            // popUpMenu(_:) is deprecated since macOS 10.14.
            // Show the menu directly using NSMenu.popUp so left-click
            // continues to use the button's action (panel toggle).
            buildStatusMenu().popUp(positioning: nil,
                                    at: NSPoint(x: 0, y: sender.bounds.height),
                                    in: sender)
        } else {
            panelController?.toggle()
        }
    }

    // MARK: - Status Bar Menu

    /// Builds the right-click menu fresh each time so the Launch at Login
    /// checkmark always reflects the current `SMAppService` state.
    private func buildStatusMenu() -> NSMenu {
        let menu = NSMenu()

        let loginItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        loginItem.target = self
        loginItem.state  = launchAtLoginEnabled ? .on : .off
        menu.addItem(loginItem)

        // History Size submenu
        let sizeItem = NSMenuItem(title: "History Size", action: nil, keyEquivalent: "")
        let sizeMenu = NSMenu()
        for count in ClipboardStore.maxItemsOptions {
            let option = NSMenuItem(
                title: "\(count) items",
                action: #selector(changeMaxItems(_:)),
                keyEquivalent: ""
            )
            option.target = self
            option.tag = count
            option.state = (count == store.maxItems) ? .on : .off
            sizeMenu.addItem(option)
        }
        sizeItem.submenu = sizeMenu
        menu.addItem(sizeItem)

        // Hotkey submenu
        let hotkeyItem = NSMenuItem(title: "Hotkey", action: nil, keyEquivalent: "")
        let hotkeyMenu = NSMenu()
        let currentOption = hotkey.currentOption
        for (idx, option) in HotkeyOption.allOptions.enumerated() {
            let menuItem = NSMenuItem(
                title: option.label,
                action: #selector(changeHotkey(_:)),
                keyEquivalent: ""
            )
            menuItem.target = self
            menuItem.tag = idx
            menuItem.state = (option == currentOption) ? .on : .off
            hotkeyMenu.addItem(menuItem)
        }
        hotkeyItem.submenu = hotkeyMenu
        menu.addItem(hotkeyItem)

        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Quit Kclip",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        return menu
    }

    // MARK: - Launch at Login

    /// `true` when Kclip is registered to launch automatically at login.
    private var launchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    // MARK: - History Size

    /// Sets the maximum number of unpinned items from the History Size submenu.
    @objc private func changeMaxItems(_ sender: NSMenuItem) {
        store.maxItems = sender.tag
        store.trimToLimit()
    }

    /// Toggles the Launch at Login state via `SMAppService` (macOS 13+).
    @objc private func toggleLaunchAtLogin() {
        do {
            if launchAtLoginEnabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            // Registration can fail if the user denies the request in System Settings.
            // Silent failure is acceptable; the user can retry from the menu.
        }
    }

    // MARK: - Setup: Floating Panel

    private func setupFloatingPanel() {
        panelController = FloatingPanelController(store: store, pasteHelper: pasteHelper)
    }

    // MARK: - Setup: Clipboard Monitor

    private func setupClipboardMonitor() {
        monitor.onNewItem = { [weak self] item in
            self?.store.add(item)
        }
        monitor.start()
    }

    // MARK: - Setup: Global Hotkey

    private func setupHotkey() {
        hotkey.onActivate = { [weak self] in
            self?.panelController?.toggle()
        }

        hotkey.onRegistrationFailed = { [weak self] _, _ in
            guard let self else { return }
            let label = self.hotkey.currentOption.label
            let alert = NSAlert()
            alert.messageText = "Hotkey registration failed"
            alert.informativeText =
                "Kclip could not register \(label). The shortcut may conflict with another app. " +
                "You can change it from the menu bar icon (right-click → Hotkey)."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }

        let saved = HotkeyOption.load()
        hotkey.register(keyCode: saved.keyCode, modifiers: saved.modifiers)
    }

    // MARK: - Hotkey Change

    @objc private func changeHotkey(_ sender: NSMenuItem) {
        let idx = sender.tag
        guard idx >= 0, idx < HotkeyOption.allOptions.count else { return }
        let option = HotkeyOption.allOptions[idx]
        if !hotkey.switchTo(option) {
            let alert = NSAlert()
            alert.messageText = "Hotkey conflict"
            alert.informativeText =
                "Could not register \(option.label). It may conflict with another app. " +
                "The previous hotkey has been restored."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
            // Re-register the previous hotkey
            let fallback = HotkeyOption.load()
            hotkey.switchTo(fallback)
        }
    }

    // MARK: - Accessibility Check

    /// UserDefaults key written once the user has seen the accessibility prompt.
    /// Prevents the alert from firing on every launch when macOS doesn't yet
    /// reflect the granted permission (common during development builds).
    private static let accessibilityPromptedKey = "cc.kclip.hasPromptedForAccessibility"

    private func checkAccessibility() {
        // Already trusted — nothing to do.
        guard !PasteHelper.hasAccessibilityPermission else { return }

        // Already asked once before — don't nag on every launch.
        // The user can grant access at any time via System Settings.
        guard !UserDefaults.standard.bool(forKey: Self.accessibilityPromptedKey) else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let alert = NSAlert()
            alert.messageText = "Kclip needs Accessibility access"
            alert.informativeText =
                "To paste clipboard items into other apps using keyboard shortcuts, " +
                "Kclip requires Accessibility permission.\n\n" +
                "Please click \"Open System Settings\", then enable Kclip under " +
                "Privacy & Security → Accessibility."
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Later")
            alert.alertStyle = .warning

            // Mark as prompted so this alert never fires again on future launches.
            UserDefaults.standard.set(true, forKey: Self.accessibilityPromptedKey)

            if alert.runModal() == .alertFirstButtonReturn {
                PasteHelper.requestAccessibilityPermission()
            }
        }
    }
}
