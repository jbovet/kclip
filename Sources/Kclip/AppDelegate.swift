// AppDelegate.swift
// Kclip – Open-source keyboard-first clipboard manager
// Wires together: menu bar icon, clipboard monitoring, global hotkey, floating panel.

import AppKit
import SwiftUI
import ServiceManagement

extension Notification.Name {
    /// Posted by the SwiftUI ⌘, command (see ``KclipApp``) to ask the delegate
    /// to open its Preferences window. Keeps a single window for both the ⌘,
    /// shortcut and the status-bar "Preferences…" item.
    static let openKclipPreferences = Notification.Name("cc.kclip.openPreferences")
}

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

    /// Shared clipboard history store. Exposed (non-private) so the SwiftUI
    /// `Settings` scene in ``KclipApp`` can bind the same instance the monitor
    /// and panel use.
    let store               = ClipboardStore()
    private let monitor     = ClipboardMonitor()
    private let pasteHelper = PasteHelper()
    private let hotkey      = HotkeyManager.shared

    // MARK: - UI

    private var statusItem: NSStatusItem?
    private var panelController: FloatingPanelController?
    /// Retained Preferences window. Built lazily on first open and reused.
    private var settingsWindow: NSWindow?

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

        // ⌘, from the SwiftUI command (KclipApp) opens the same custom window
        // as the status-bar "Preferences…" item, so there is only ever one.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(openPreferences),
            name: .openKclipPreferences,
            object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
        hotkey.unregister()
        store.clearOnQuitIfNeeded()
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

    /// Builds the right-click menu: Preferences… and Quit. All configurable
    /// options now live in the Preferences window (``SettingsView``).
    private func buildStatusMenu() -> NSMenu {
        let menu = NSMenu()

        let prefsItem = NSMenuItem(
            title: "Preferences…",
            action: #selector(openPreferences),
            keyEquivalent: ","
        )
        prefsItem.target = self
        menu.addItem(prefsItem)

        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Quit Kclip",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        return menu
    }

    /// Opens the Preferences window, building it lazily on first use.
    ///
    /// Kclip hosts ``SettingsView`` in its own `NSWindow` rather than the SwiftUI
    /// `Settings` scene: the scene's programmatic openers (`showSettingsWindow:`)
    /// are unreliable for accessory (menu-bar) apps on recent macOS and fail with
    /// a task-port error when no app window is already key. A plain window works
    /// from any context. `activate` brings it forward since Kclip is an accessory.
    @objc private func openPreferences() {
        if settingsWindow == nil {
            let hosting = NSHostingController(rootView: SettingsView(store: store))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Kclip Preferences"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false   // reuse across opens
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
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
                "You can change it in Preferences (menu bar icon → Preferences… → Shortcuts)."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }

        let saved = HotkeyOption.load()
        hotkey.register(keyCode: saved.keyCode, modifiers: saved.modifiers)
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
