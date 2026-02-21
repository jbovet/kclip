// HotkeyManager.swift
// Kclip – Open-source keyboard-first clipboard manager
// Registers a global hotkey using Carbon so it fires even when other apps are focused.

import Carbon.HIToolbox
import AppKit

// MARK: - HotkeyOption

/// A predefined hotkey combination that the user can choose from the status-bar menu.
struct HotkeyOption: Equatable {
    /// Display label shown in the menu (e.g. "⌘⇧V").
    let label: String
    /// Carbon virtual key code (`kVK_*`).
    let keyCode: UInt32
    /// Carbon modifier flags (e.g. `cmdKey | shiftKey`).
    let modifiers: UInt32

    /// All available hotkey choices.
    static let allOptions: [HotkeyOption] = [
        HotkeyOption(label: "⌘⇧V", keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | shiftKey)),
        HotkeyOption(label: "⌘⇧C", keyCode: UInt32(kVK_ANSI_C), modifiers: UInt32(cmdKey | shiftKey)),
        HotkeyOption(label: "⌃⇧V",  keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(controlKey | shiftKey)),
        HotkeyOption(label: "⌥⇧V",  keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(optionKey | shiftKey)),
        HotkeyOption(label: "⌘⇧B", keyCode: UInt32(kVK_ANSI_B), modifiers: UInt32(cmdKey | shiftKey)),
    ]

    /// The default hotkey (⌘⇧V).
    static let defaultOption = allOptions[0]

    /// Returns the option matching the given key code and modifiers, or `nil`.
    static func find(keyCode: UInt32, modifiers: UInt32) -> HotkeyOption? {
        allOptions.first { $0.keyCode == keyCode && $0.modifiers == modifiers }
    }

    // MARK: - Persistence

    private static let keyCodeKey   = "cc.kclip.hotkeyKeyCode"
    private static let modifiersKey = "cc.kclip.hotkeyModifiers"

    /// Loads the saved hotkey from UserDefaults, falling back to the default.
    static func load() -> HotkeyOption {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: keyCodeKey) != nil else { return defaultOption }
        let code = UInt32(defaults.integer(forKey: keyCodeKey))
        let mods = UInt32(defaults.integer(forKey: modifiersKey))
        return find(keyCode: code, modifiers: mods) ?? defaultOption
    }

    /// Persists the hotkey choice to UserDefaults.
    func save() {
        let defaults = UserDefaults.standard
        defaults.set(Int(keyCode), forKey: Self.keyCodeKey)
        defaults.set(Int(modifiers), forKey: Self.modifiersKey)
    }
}

// MARK: - HotkeyManager

/// Registers a system-wide keyboard shortcut using the Carbon `RegisterEventHotKey` API.
///
/// The hotkey fires even when another application is in focus — the same mechanism
/// used by Alfred and Raycast. Use the ``shared`` singleton and set ``onActivate``
/// before calling ``register(keyCode:modifiers:)``.
///
/// - Note: This API is not available inside the macOS App Sandbox.
final class HotkeyManager {

    // MARK: - Singleton

    /// The shared instance. Use this instead of creating new instances.
    static let shared = HotkeyManager()

    // MARK: - State

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    /// Called on the main thread when the registered hotkey is pressed.
    var onActivate: (() -> Void)?

    /// Called on the main thread if hotkey registration fails (e.g. conflict with another app).
    /// Provides the `OSStatus` error codes from `InstallEventHandler` and `RegisterEventHotKey`.
    var onRegistrationFailed: ((_ installStatus: OSStatus, _ registerStatus: OSStatus) -> Void)?

    /// `true` after ``register(keyCode:modifiers:)`` completes successfully.
    private(set) var isRegistered: Bool = false

    /// The currently active hotkey option, updated on each successful registration.
    private(set) var currentOption: HotkeyOption = .defaultOption

    // MARK: - Register

    /// Registers the global hotkey with the system.
    ///
    /// - Parameters:
    ///   - keyCode: Virtual key code (Carbon `kVK_*`). Default is `kVK_ANSI_V` (V key).
    ///   - modifiers: Carbon modifier flags. Default is `cmdKey | shiftKey` (⌘⇧).
    func register(
        keyCode: UInt32 = UInt32(kVK_ANSI_V),
        modifiers: UInt32 = UInt32(cmdKey | shiftKey)
    ) {
        // Carbon hotkey signature: "CCIP" in four chars
        let hotKeyID = EventHotKeyID(signature: 0x43434950, id: 1)

        // Event spec: keyboard hotkey pressed
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        // We pass `self` as user data via raw pointer (unretained – we manage lifetime)
        let selfPtr = UnsafeMutableRawPointer(
            Unmanaged.passUnretained(self).toOpaque()
        )

        let handlerCallback: EventHandlerUPP = { _, _, userData -> OSStatus in
            guard let ptr = userData else { return noErr }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(ptr).takeUnretainedValue()
            DispatchQueue.main.async { manager.onActivate?() }
            return noErr
        }

        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            handlerCallback,
            1,
            &eventSpec,
            selfPtr,
            &eventHandlerRef
        )

        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if installStatus == noErr && registerStatus == noErr {
            isRegistered = true
            currentOption = HotkeyOption.find(keyCode: keyCode, modifiers: modifiers) ?? .defaultOption
        } else {
            isRegistered = false
            let install  = installStatus
            let register = registerStatus
            DispatchQueue.main.async { [weak self] in
                self?.onRegistrationFailed?(install, register)
            }
        }
    }

    /// Unregisters the current hotkey, registers a new one, and persists the choice.
    /// - Parameter option: The hotkey option to switch to.
    /// - Returns: `true` if re-registration succeeded.
    @discardableResult
    func switchTo(_ option: HotkeyOption) -> Bool {
        unregister()
        register(keyCode: option.keyCode, modifiers: option.modifiers)
        if isRegistered {
            option.save()
        }
        return isRegistered
    }

    // MARK: - Unregister

    /// Unregisters the hotkey and removes the event handler. Called automatically on `deinit`.
    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let ref = eventHandlerRef {
            RemoveEventHandler(ref)
            eventHandlerRef = nil
        }
        isRegistered = false
    }

    deinit { unregister() }
}
