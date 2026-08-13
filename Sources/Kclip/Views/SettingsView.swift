// SettingsView.swift
// Kclip – Open-source keyboard-first clipboard manager
// The Preferences window: General / Privacy / Shortcuts tabs.
// Hosted by the SwiftUI `Settings` scene in KclipApp and opened via ⌘, or the
// status-bar menu. Binds the same `ClipboardStore`, `HotkeyManager`, and
// `SMAppService` state that the running app uses, so changes take effect live.

import SwiftUI
import ServiceManagement
import AppKit

// MARK: - Root

/// Tabbed Preferences window for Kclip.
struct SettingsView: View {

    /// The shared history store (same instance the monitor and panel use).
    @ObservedObject var store: ClipboardStore

    var body: some View {
        TabView {
            GeneralSettingsView(store: store)
                .tabItem { Label("General", systemImage: "gearshape") }

            PrivacySettingsView()
                .tabItem { Label("Privacy", systemImage: "hand.raised") }

            ShortcutsSettingsView()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
        }
        // Fixed size so the hosting NSWindow has a sensible frame; the Privacy
        // tab's exclusion list scrolls within the Form if it overflows.
        .frame(width: 480, height: 360)
    }
}

// MARK: - General

/// History size and launch-at-login.
private struct GeneralSettingsView: View {

    @ObservedObject var store: ClipboardStore

    /// Mirrors `store.maxItems` in `@State` so the Picker drives SwiftUI updates;
    /// `store.maxItems` is a UserDefaults-backed computed property, not `@Published`.
    /// Seeded to the default; `onAppear` syncs it to the real store value.
    @State private var historySize = 15
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Picker("History size", selection: $historySize) {
                ForEach(ClipboardStore.maxItemsOptions, id: \.self) { count in
                    Text("\(count) items").tag(count)
                }
            }
            .onChange(of: historySize) { newValue in
                store.maxItems = newValue
                store.trimToLimit()
            }

            Toggle("Launch Kclip at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { newValue in
                    setLaunchAtLogin(newValue)
                    // Reflect the real state — registration can be denied.
                    launchAtLogin = SMAppService.mainApp.status == .enabled
                }

            Text("Kclip keeps up to \(historySize) unpinned items, plus all pinned items.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        // Re-sync on each open so the window reflects changes made via the
        // status-bar submenus while it was hidden.
        .onAppear {
            historySize = store.maxItems
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else       { try SMAppService.mainApp.unregister() }
        } catch {
            // Registration can fail if the user denies it in System Settings.
            // The onChange handler re-reads the real status, so the toggle
            // snaps back if the change didn't stick.
        }
    }
}

// MARK: - Privacy

/// Read-only privacy status: Accessibility permission and the built-in
/// app-exclusion list. Editable controls arrive with the privacy issues (#6–#8).
private struct PrivacySettingsView: View {

    @State private var hasAccessibility = PasteHelper.hasAccessibilityPermission

    var body: some View {
        Form {
            Section("Pasting") {
                HStack(spacing: 10) {
                    Image(systemName: hasAccessibility
                          ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(hasAccessibility ? .green : .orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Accessibility permission")
                        Text(hasAccessibility
                             ? "Granted — Kclip can paste into other apps."
                             : "Not granted — items are copied but not auto-pasted.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !hasAccessibility {
                        Button("Open System Settings") {
                            PasteHelper.requestAccessibilityPermission()
                        }
                    }
                }
            }

            Section("Excluded apps") {
                Text("Clipboard content from these apps is never captured:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(ClipboardMonitor.defaultExcludedBundleIDs.sorted(), id: \.self) { bundleID in
                    Text(bundleID)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        // Re-read permission when the window regains focus (e.g. after the user
        // grants it in System Settings and comes back).
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in
            hasAccessibility = PasteHelper.hasAccessibilityPermission
        }
    }
}

// MARK: - Shortcuts

/// The global hotkey used to summon the Kclip panel.
private struct ShortcutsSettingsView: View {

    @State private var selection = HotkeyManager.shared.currentOption
    @State private var showConflict = false

    var body: some View {
        Form {
            Picker("Global shortcut", selection: $selection) {
                ForEach(HotkeyOption.allOptions, id: \.self) { option in
                    Text(option.label).tag(option)
                }
            }
            .onChange(of: selection) { newValue in
                guard newValue != HotkeyManager.shared.currentOption else { return }
                let previous = HotkeyManager.shared.currentOption
                if !HotkeyManager.shared.switchTo(newValue) {
                    // Conflict: switchTo already unregistered the previous binding,
                    // so re-register it (leaving no hotkey at all would be worse)
                    // and snap the picker back.
                    showConflict = true
                    HotkeyManager.shared.switchTo(previous)
                    selection = HotkeyManager.shared.currentOption
                }
            }

            Text("Press this shortcut in any app to open the Kclip panel.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        // Reflect the current binding on each open (it may have changed via the menu).
        .onAppear { selection = HotkeyManager.shared.currentOption }
        .alert("Shortcut unavailable", isPresented: $showConflict) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("That shortcut conflicts with another app. The previous one was kept.")
        }
    }
}
