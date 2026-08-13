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
        // The app has no regular windows — it lives in the menu bar. Preferences
        // is hosted in its own NSWindow by AppDelegate (the SwiftUI Settings
        // scene's programmatic openers are unreliable for accessory apps), so
        // this scene is just the required minimal stub.
        Settings {
            EmptyView()
        }
        // Replace the default "Settings…" command so ⌘, never opens the empty
        // SwiftUI Settings window; instead it asks AppDelegate to show the one
        // real Preferences window (same one the status-bar item opens).
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Preferences…") {
                    NotificationCenter.default.post(name: .openKclipPreferences, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
