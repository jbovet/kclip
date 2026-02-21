// PasteHelper.swift
// Kclip – Open-source keyboard-first clipboard manager
// Puts text on the clipboard and simulates ⌘V in the previously focused app.
// Requires Accessibility permission (prompted automatically on first use).

import AppKit
import Carbon

/// Pastes text into the previously focused application by simulating ⌘V.
///
/// **Workflow:**
/// 1. Call ``snapshotFrontApp()`` before showing the Kclip panel.
/// 2. Call ``paste(_:completion:)`` after the user selects an item.
///
/// Simulating ⌘V via `CGEvent` requires Accessibility permission.
/// Use ``hasAccessibilityPermission`` to check and ``requestAccessibilityPermission()``
/// to prompt the system dialog.
///
/// - Note: This class is not available inside the macOS App Sandbox.
final class PasteHelper {

    // MARK: - Configuration

    /// Time (seconds) to wait for the target app to become key before sending ⌘V.
    private static let pasteDelay: TimeInterval = 0.08

    // MARK: - State

    /// The app that was frontmost before Kclip's panel appeared.
    /// Set by ``snapshotFrontApp()``.
    private(set) var previousApp: NSRunningApplication?

    // MARK: - Snapshot

    /// Captures the current frontmost application so ``paste(_:completion:)`` knows
    /// where to send the ⌘V event.
    ///
    /// Skips Kclip itself so we always capture the true previous app.
    /// Call this before showing the Kclip panel.
    func snapshotFrontApp() {
        let front = NSWorkspace.shared.frontmostApplication
        if front?.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousApp = front
        }
    }

    // MARK: - Paste

    /// Pastes `text` into the application captured by ``snapshotFrontApp()``.
    ///
    /// Steps performed:
    /// 1. Writes `text` to `NSPasteboard`.
    /// 2. Re-activates the previously focused app.
    /// 3. Waits 80 ms for the app to become key, then sends a ⌘V `CGEvent`.
    ///
    /// - Parameters:
    ///   - text: The string to paste.
    ///   - completion: Optional closure called after the key event is posted.
    func paste(_ text: String, completion: (() -> Void)? = nil) {
        writeToPasteboard(text)
        guard let target = previousApp else { completion?(); return }
        target.activate(options: .activateIgnoringOtherApps)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.pasteDelay) {
            Self.simulateKeyPress(flags: .maskCommand)
            completion?()
        }
    }

    /// Pastes `text` as plain text by simulating ⌘⌥⇧V (Paste and Match Style).
    ///
    /// Many macOS apps (Safari, Pages, Notes, Mail, Google Docs) interpret
    /// ⌘⌥⇧V as "Paste and Match Style", which strips any formatting and
    /// pastes only the plain text content.
    ///
    /// - Parameters:
    ///   - text: The string to paste.
    ///   - completion: Optional closure called after the key event is posted.
    func pastePlainText(_ text: String, completion: (() -> Void)? = nil) {
        writeToPasteboard(text)
        guard let target = previousApp else { completion?(); return }
        target.activate(options: .activateIgnoringOtherApps)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.pasteDelay) {
            Self.simulateKeyPress(flags: [.maskCommand, .maskAlternate, .maskShift])
            completion?()
        }
    }

    // MARK: - Private

    private func writeToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private static func simulateKeyPress(flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        let vKey: CGKeyCode = CGKeyCode(kVK_ANSI_V)

        let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        let up   = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)

        down?.flags = flags
        up?.flags   = flags

        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    // MARK: - Accessibility Permission

    /// Returns true if Accessibility access has been granted.
    static var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system dialog to grant Accessibility permission.
    /// Call once at app launch if permission is missing.
    static func requestAccessibilityPermission() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}
