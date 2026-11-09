// AccessibilityStatus.swift
// Kclip – Open-source keyboard-first clipboard manager
// Pure helper describing the app's Accessibility-permission state for the UI.

import Foundation

/// Stateless helpers for presenting the Accessibility-permission status in
/// Preferences → Privacy. Kept separate from the view so the wording — in
/// particular the restart caveat — can be unit-tested.
enum AccessibilityStatus {

    /// The status line shown under "Accessibility permission".
    ///
    /// - Parameters:
    ///   - granted: Whether `AXIsProcessTrusted()` currently returns `true`.
    ///   - grantedThisSession: Whether permission flipped from denied to granted
    ///     while Kclip was already running. In that case pasting may still fail
    ///     for the current process — TCC can cache the earlier denial at the
    ///     event-tap layer, especially for unsigned builds — so we nudge a
    ///     restart as a fallback rather than promising it works immediately.
    /// - Returns: A human-readable status sentence.
    static func message(granted: Bool, grantedThisSession: Bool) -> String {
        guard granted else {
            return "Not granted — items are copied but not auto-pasted."
        }
        return grantedThisSession
            ? "Granted. If pasting still doesn't work, restart Kclip."
            : "Granted — Kclip can paste into other apps."
    }
}
