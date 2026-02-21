// KclipApp.swift
// Kclip – Open-source keyboard-first clipboard manager
// App entry point. All setup is delegated to AppDelegate.

import SwiftUI

/// SwiftUI entry point for Kclip.
///
/// The app has no visible windows — it lives entirely in the menu bar.
/// All initialisation is delegated to ``AppDelegate`` via `@NSApplicationDelegateAdaptor`.
/// The `Settings` scene is a no-op required to satisfy the `App` protocol on macOS.
@main
struct KclipApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No windows — the app lives entirely in the menu bar.
        // A Settings scene is provided so the app can open system preferences.
        Settings {
            EmptyView()
        }
    }
}
