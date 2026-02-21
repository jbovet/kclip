// FloatingPanel.swift
// Kclip – Open-source keyboard-first clipboard manager
// A borderless, always-on-top NSPanel that hosts our SwiftUI popup.
// Appears centered on the active screen, above all other windows.

import AppKit
import SwiftUI

extension Notification.Name {
    static let clipClipPanelWillShow = Notification.Name("cc.kclip.panelWillShow")
}

// MARK: - FloatingPanel (NSPanel subclass)

/// A borderless, always-on-top `NSPanel` that hosts the clipboard popup.
///
/// Configured to appear on all Spaces at `.popUpMenu` window level,
/// above full-screen apps. Escape key is forwarded via `cancelOperation(_:)`
/// so it works regardless of SwiftUI focus state.
final class FloatingPanel: NSPanel {

    init() {

        super.init(
            contentRect: .zero,
            styleMask: [
                .fullSizeContentView,  // Content fills entire window area
                .borderless            // No title bar
            ],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel             = true
        level                       = .popUpMenu          // Above everything, including full-screen
        isOpaque                    = false
        backgroundColor             = .clear
        hasShadow                   = true
        isMovableByWindowBackground = false
        // Show on all Spaces, not cycling in Mission Control
        collectionBehavior          = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        animationBehavior           = .utilityWindow
        // Accept key events so local NSEvent monitors and SwiftUI focus work
        hidesOnDeactivate           = false
    }

    // Allow the panel to become key so SwiftUI text fields and key monitors work
    override var canBecomeKey: Bool  { true }
    override var canBecomeMain: Bool { true }

    // Called by AppKit when Escape is pressed — reliable regardless of local monitors
    override func cancelOperation(_ sender: Any?) {
        NotificationCenter.default.post(name: .clipClipPanelEscapePressed, object: nil)
    }
}

extension Notification.Name {
    static let clipClipPanelEscapePressed = Notification.Name("cc.kclip.escapePressed")
    /// Posted when a clipboard item is selected but no previous app was captured,
    /// so the text was only written to the clipboard (not pasted via ⌘V).
    static let clipClipCopiedOnly = Notification.Name("cc.kclip.copiedOnly")
}

// MARK: - KeyEventBridge

/// Shared reference-type object that bridges key events from ``FloatingPanelController``
/// (which owns the local `NSEvent` monitor) to ``ClipboardPopupView`` (which owns the
/// action closures).
///
/// The monitor is installed in ``FloatingPanelController/show()`` and torn down in
/// ``FloatingPanelController/hide()``, tying its lifecycle to the panel's visibility
/// rather than to fragile SwiftUI view-hierarchy events.
///
/// ``ClipboardPopupView`` refreshes the action closures via a lightweight
/// `NSViewRepresentable` (`BridgeUpdater`) on every SwiftUI render cycle. Because
/// `isSearchActive` is stored as `() -> Bool` (not `Bool`), calling it always reads
/// the current SwiftUI `@State` value through the property-wrapper backing store —
/// even if the closure was captured from a slightly older view-struct value.
final class KeyEventBridge {
    var onUp:             () -> Void    = {}
    var onDown:           () -> Void    = {}
    var onReturn:         () -> Void    = {}
    var onOptionReturn:   () -> Void    = {}
    var onEscape:         () -> Void    = {}
    var onDelete:         () -> Void    = {}
    var onPin:            () -> Void    = {}
    var onSpace:          () -> Void    = {}
    var onUndo:           () -> Void    = {}
    var onDigit:          (Int) -> Void = { _ in }
    /// Returns `true` when Del / P / Space should be passed through to the text field.
    /// Stored as a closure so it reads fresh `@State` on every invocation.
    var isSearchActive: () -> Bool = { false }

    /// Dispatches a key-down event. Returns `nil` (consuming the event) when handled,
    /// or the original event when the key should be forwarded to the first responder.
    func handle(_ event: NSEvent) -> NSEvent? {
        let modifiers   = event.modifierFlags.intersection([.command, .option, .control])
        let noModifiers = modifiers.isEmpty

        if noModifiers {
            // Navigation — always active
            switch event.keyCode {
            case 126: onUp();     return nil   // ↑
            case 125: onDown();   return nil   // ↓
            case 36:  onReturn(); return nil   // Return
            case 76:  onReturn(); return nil   // numpad Enter
            // Escape (53) is handled by FloatingPanel.cancelOperation — do not consume here
            default: break
            }

            // Space — preview, only when search is empty and no preview is open
            if !isSearchActive() && event.keyCode == 49 { onSpace(); return nil }

            // Items 1–9 (top-row and numpad), 0 = item 10
            let topRow: [UInt16: Int] = [18:1, 19:2, 20:3, 21:4, 23:5, 22:6, 26:7, 28:8, 25:9, 29:10]
            let numpad: [UInt16: Int] = [83:1, 84:2, 85:3, 86:4, 87:5, 88:6, 89:7, 91:8, 92:9, 82:10]
            if let digit = topRow[event.keyCode] ?? numpad[event.keyCode] {
                onDigit(digit); return nil
            }
        }

        // ⌥Return — paste as plain text
        if modifiers == .option {
            if event.keyCode == 36 || event.keyCode == 76 {
                onOptionReturn(); return nil
            }
        }

        // ⌘-modified shortcuts (Command only, no Option/Control)
        if modifiers == .command {
            switch event.keyCode {
            case 51: onDelete(); return nil   // ⌘Delete — delete selected item
            case 35: onPin();    return nil   // ⌘P     — pin / unpin selected item
            case 6:  onUndo();   return nil   // ⌘Z     — undo last delete
            default: break
            }
            // Items 11–15 via ⌘1–⌘5
            let cmdDigits: [UInt16: Int] = [18:11, 19:12, 20:13, 21:14, 23:15]
            if let digit = cmdDigits[event.keyCode] { onDigit(digit); return nil }
        }

        return event
    }
}

// MARK: - FloatingPanelController

/// Manages the lifecycle of the ``FloatingPanel``: creation, showing, hiding, and centering.
///
/// The panel is created lazily on the first ``show()`` call and reused for the lifetime
/// of the app. A global mouse monitor hides the panel when the user clicks outside it.
final class FloatingPanelController: NSObject, NSWindowDelegate {

    // MARK: - Timing Constants

    /// Duration (seconds) of the fade-in animation when showing the panel.
    private static let showAnimationDuration: TimeInterval = 0.15
    /// Duration (seconds) of the fade-out animation when hiding the panel.
    private static let hideAnimationDuration: TimeInterval = 0.12
    /// How long (seconds) the "Copied to clipboard" banner is shown before auto-hiding the panel
    /// when no previous app was captured (cold-open fallback).
    private static let copiedOnlyAutoHideDelay: TimeInterval = 1.3

    // MARK: - Dependencies

    private let store: ClipboardStore
    private let pasteHelper: PasteHelper

    // MARK: - State

    private var panel: FloatingPanel?
    /// Retained so `show()` can ask for `fittingSize` on every open,
    /// letting the panel height adapt to the current item count.
    private var hostingView: NSView?
    private var mouseMonitor: Any?
    /// Key-event bridge shared with ClipboardPopupView.
    /// The local key monitor is installed here (in show/hide) so its lifetime is tied to
    /// panel visibility — not to the fragile SwiftUI NSViewRepresentable view hierarchy.
    let bridge = KeyEventBridge()
    private var keyMonitor: Any?

    // MARK: - Init

    /// Creates the controller. The panel itself is not built until the first ``show()`` call.
    /// - Parameters:
    ///   - store: The shared clipboard history store.
    ///   - pasteHelper: The helper used to snapshot and paste into the previous app.
    init(store: ClipboardStore, pasteHelper: PasteHelper) {
        self.store       = store
        self.pasteHelper = pasteHelper
    }

    // MARK: - Public

    /// `true` when the panel is currently visible on screen.
    var isVisible: Bool { panel?.isVisible == true }

    /// Shows the panel if hidden, or hides it if already visible.
    func toggle() {
        if isVisible { hide() } else { show() }
    }

    /// Shows the panel centered on the active screen with a fade-in animation.
    ///
    /// Also snapshots the frontmost app (for later paste) and installs a global
    /// mouse monitor that dismisses the panel on outside clicks.
    func show() {
        // Remember the app that's currently focused (we'll paste into it later)
        pasteHelper.snapshotFrontApp()

        if panel == nil { buildPanel() }
        guard let panel else { return }

        // Resize the panel to fit the current item count before centering.
        // fittingSize reflects the SwiftUI view's natural height, which respects
        // the maxListHeight cap in ClipboardPopupView, so the panel is tall when
        // there are many items and short when there are only a few.
        if let hosting = hostingView {
            panel.setContentSize(hosting.fittingSize)
        }

        centerOnActiveScreen(panel)

        // Notify the popup to reset its state (clear search, reset selection)
        NotificationCenter.default.post(name: .clipClipPanelWillShow, object: nil)

        // Hide when user clicks outside the panel.
        // Guard prevents double-install if show() is called without a matching hide().
        if mouseMonitor == nil {
            mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.hide()
            }
        }

        // Install the key monitor now that the panel is becoming visible.
        // Owning the monitor here (rather than inside an NSViewRepresentable) means it is
        // never silently removed by SwiftUI view-hierarchy changes (focus shifts, ZStack
        // additions/removals, etc.).
        if keyMonitor == nil {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                return self?.bridge.handle(event) ?? event
            }
        }

        // Ensure app is active so the panel can become key window in all code paths
        // (menu bar click does not guarantee app activation before makeKeyAndOrderFront)
        NSApp.activate(ignoringOtherApps: true)

        // Animate in
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Self.showAnimationDuration
            panel.animator().alphaValue = 1
        }
    }

    /// Hides the panel with a fade-out animation.
    func hide() {
        guard let panel, panel.isVisible else { return }

        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }

        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = Self.hideAnimationDuration
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }

    // MARK: - NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        // Hide when a sheet (e.g. NSAlert) is not the cause of resign
        guard let panel = notification.object as? NSPanel,
              panel.attachedSheet == nil else { return }
        hide()
    }

    // MARK: - Private

    /// Shared paste logic for both normal paste and paste-as-plain-text.
    private func performPaste(_ text: String, plainText: Bool) {
        if pasteHelper.previousApp != nil {
            hide()
            if plainText {
                pasteHelper.pastePlainText(text)
            } else {
                pasteHelper.paste(text)
            }
        } else {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(text, forType: .string)
            NotificationCenter.default.post(name: .clipClipCopiedOnly, object: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.copiedOnlyAutoHideDelay) { [weak self] in
                self?.hide()
            }
        }
    }

    private func buildPanel() {
        let newPanel = FloatingPanel()
        newPanel.delegate = self

        let popup = ClipboardPopupView(
            store: store,
            bridge: bridge,
            onPaste: { [weak self] item in
                self?.performPaste(item.content, plainText: false)
            },
            onPastePlainText: { [weak self] item in
                self?.performPaste(item.content, plainText: true)
            },
            onDismiss: { [weak self] in
                self?.hide()
            },
            onQuit: {
                NSApp.terminate(nil)
            }
        )

        let hosting = NSHostingView(rootView: popup)
        // Width is fixed; height will be set to fittingSize in show() on every open.
        hosting.frame = NSRect(x: 0, y: 0, width: 580, height: 400)

        newPanel.contentView = hosting
        hostingView = hosting
        panel = newPanel
    }

    private func centerOnActiveScreen(_ panel: NSPanel) {
        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
                  ?? NSScreen.main
                  ?? NSScreen.screens[0]

        let screenFrame = screen.visibleFrame
        let panelSize   = panel.frame.size
        let x = screenFrame.midX - panelSize.width  / 2
        // Place panel slightly above center (Spotlight-style)
        let y = screenFrame.midY - panelSize.height / 2 + screenFrame.height * 0.1

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
