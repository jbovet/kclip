// ClipboardMonitor.swift
// Kclip – Open-source keyboard-first clipboard manager
// Polls NSPasteboard and fires a callback when new text is copied

import AppKit
import Foundation

/// Watches the system clipboard for new text by polling `NSPasteboard` at a fixed interval.
///
/// Start monitoring with ``start()`` and stop it with ``stop()``.
/// Assign ``onNewItem`` to receive new clipboard entries on the main thread.
///
/// - Note: Only plain text (`NSPasteboard.PasteboardType.string`) is captured.
///   Images and files are ignored and can be added by extending `checkPasteboard()`.
final class ClipboardMonitor {

    // MARK: - Configuration

    /// How often (in seconds) the pasteboard is checked. 0.5 s feels instant.
    private let pollInterval: TimeInterval = 0.5

    /// Bundle identifiers of apps whose clipboard content is **never** captured.
    ///
    /// Password managers and other credential tools are excluded by default so
    /// that sensitive secrets don't end up stored in plain text in clipboard history.
    ///
    /// Users may extend the list at runtime by appending bundle IDs to the
    /// `cc.kclip.excludedBundleIDs` UserDefaults array.
    static let defaultExcludedBundleIDs: Set<String> = [
        "com.agilebits.onepassword7",       // 1Password 7
        "com.agilebits.onepassword-osx",    // 1Password (classic)
        "com.1password.1password",          // 1Password 8
        "com.bitwarden.desktop",            // Bitwarden
        "com.lastpass.LastPass",            // LastPass
        "com.dashlane.Dashlane",            // Dashlane
        "in.sinew.Enpass-Desktop",          // Enpass
        "com.keepassium.KeePassium",        // KeePassium
        "org.keepassxc.keepassxc",          // KeePassXC
        "com.googlecode.keepassx",          // KeePassX
        "com.apple.Passwords",              // Apple Passwords (macOS 15+)
    ]

    /// Returns the full exclusion set: defaults plus any bundle IDs the user
    /// added via `UserDefaults.standard["cc.kclip.excludedBundleIDs"]`.
    private var excludedBundleIDs: Set<String> {
        let extras = (UserDefaults.standard
            .array(forKey: "cc.kclip.excludedBundleIDs") as? [String])
            .map(Set.init) ?? []
        return Self.defaultExcludedBundleIDs.union(extras)
    }

    // MARK: - State

    private var timer: Timer?
    private var lastChangeCount: Int = NSPasteboard.general.changeCount

    /// Called on the main thread whenever new text is detected on the clipboard.
    var onNewItem: ((ClipboardItem) -> Void)?

    /// The bundle ID of the last app whose clipboard content was silently excluded,
    /// along with the timestamp. Useful for debugging / status display.
    private(set) var lastExcludedApp: (bundleID: String, date: Date)?

    /// Total number of clipboard changes silently excluded since launch.
    private(set) var excludedCount: Int = 0

    // MARK: - Lifecycle

    /// Begins polling the clipboard. Safe to call more than once; subsequent calls are no-ops.
    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(
            withTimeInterval: pollInterval,
            repeats: true
        ) { [weak self] _ in
            self?.checkPasteboard()
        }
        // Add to RunLoop so it fires even during menu tracking
        RunLoop.main.add(timer!, forMode: .common)
    }

    /// Stops polling and releases the timer.
    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Internal

    private func checkPasteboard() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        // Skip capture when a password manager or other sensitive app is frontmost.
        // This prevents passwords and secrets from being stored in clipboard history.
        if let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           excludedBundleIDs.contains(bundleID) {
            lastExcludedApp = (bundleID: bundleID, date: Date())
            excludedCount += 1
            return
        }

        // We focus on plain text for now; images/files can be added later
        if let string = pasteboard.string(forType: .string),
           !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let item = ClipboardItem(content: string)
            DispatchQueue.main.async { [weak self] in
                self?.onNewItem?(item)
            }
        }
    }
}
