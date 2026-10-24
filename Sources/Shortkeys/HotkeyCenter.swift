import AppKit
import Carbon.HIToolbox
import KeyboardShortcuts

/// Delivers global hotkeys by registering them with the system
/// (`RegisterEventHotKey`).
///
/// The WindowServer matches registered hotkeys itself, so they keep working
/// while another process holds Secure Keyboard Entry (which hides keystrokes
/// from event taps, and which loginwindow sometimes leaves on after unlocking),
/// and they don't need the Accessibility permission. KeyboardShortcuts only
/// stores shortcuts and provides the recorder; its own registration is off.
@MainActor
final class HotkeyCenter {
    static let shared = HotkeyCenter()

    private var actions: [KeyboardShortcuts.Name: @MainActor @Sendable () -> Void] = [:]
    private var bindings: [KeyboardShortcuts.Shortcut: KeyboardShortcuts.Name] = [:]
    /// Registered hotkeys, by the ID the system reports when one is pressed.
    private var registered: [UInt32: (name: KeyboardShortcuts.Name, ref: EventHotKeyRef)] = [:]
    private var nextID: UInt32 = 0
    private var isRecording = false {
        didSet { if isRecording != oldValue { registerAll() } }
    }

    /// A hotkey that was just recorded for `name` but already belongs to `other`.
    struct Conflict {
        let name: KeyboardShortcuts.Name
        let other: KeyboardShortcuts.Name
        let shortcut: KeyboardShortcuts.Shortcut
        /// What `name` had before, restored if the user cancels.
        let previous: KeyboardShortcuts.Shortcut?
    }

    /// What happens on a conflict; asks the user by default. The self-test replaces it.
    var onConflict: @MainActor (Conflict) -> Void = HotkeyCenter.askToResolve

    private init() {
        var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), hotkeyPressed, 1, &pressed, nil, nil)
        if status != noErr { log.error("could not install the hotkey handler: \(status)") }

        NotificationCenter.default.observe(.shortcutDidChange, value: \.shortcutName) { name in
            HotkeyCenter.shared.shortcutChanged(name)
        }
        // Release every hotkey while the user is recording a new shortcut, so
        // the recorder receives the keys (and nothing is triggered).
        NotificationCenter.default.observe(.recorderActiveDidChange, value: \.isRecorderActive) { isActive in
            HotkeyCenter.shared.isRecording = isActive
        }
    }

    func register(_ name: KeyboardShortcuts.Name, action: @escaping @MainActor @Sendable () -> Void) {
        actions[name] = action
        rebuildBindings()
    }

    /// Removes an action registered with `register(_:action:)` (used by the self-test).
    func unregister(_ name: KeyboardShortcuts.Name) {
        actions[name] = nil
        rebuildBindings()
    }

    /// Whether a recorder is capturing a new shortcut (hotkeys are paused meanwhile).
    var isRecordingShortcut: Bool { isRecording }

    /// The action name a key combination would trigger (used by the self-test).
    func binding(for shortcut: KeyboardShortcuts.Shortcut) -> KeyboardShortcuts.Name? {
        bindings[shortcut]
    }

    /// Whether `name`'s hotkey is registered with the system (used by the self-test).
    func isRegistered(_ name: KeyboardShortcuts.Name) -> Bool {
        registered.values.contains { $0.name == name }
    }

    /// While secure input is on, macOS doesn't deliver hotkeys whose only
    /// modifiers are ⌥ and ⇧ (they type characters, e.g. into a password field).
    static func isBlockedBySecureInput(_ shortcut: KeyboardShortcuts.Shortcut) -> Bool {
        shortcut.modifiers.contains(.option) && shortcut.modifiers.isSubset(of: [.option, .shift])
    }

    /// The assigned hotkeys that pause while secure input is on.
    var blockedBySecureInput: [KeyboardShortcuts.Shortcut] {
        bindings.keys.filter(Self.isBlockedBySecureInput).sorted { "\($0)" < "\($1)" }
    }

    private func shortcutChanged(_ name: KeyboardShortcuts.Name?) {
        // `bindings` still describes the hotkeys from before this change.
        if let name, let conflict = conflict(for: name) {
            // After the recorder has finished saving and updating itself.
            Task { HotkeyCenter.shared.onConflict(conflict) }
        }
        rebuildBindings()
    }

    private func conflict(for name: KeyboardShortcuts.Name) -> Conflict? {
        guard
            let shortcut = KeyboardShortcuts.getShortcut(for: name),
            let other = bindings[shortcut],
            other != name
        else { return nil }
        let previous = bindings.first { $0.value == name }?.key
        return Conflict(name: name, other: other, shortcut: shortcut, previous: previous)
    }

    /// Asks whether to move the hotkey to the new owner or keep it where it was.
    private static func askToResolve(_ conflict: Conflict) {
        let newOwner = conflict.name.title
        let oldOwner = conflict.other.title
        let alert = NSAlert()
        alert.messageText = "“\(conflict.shortcut)” is already used by “\(oldOwner)”."
        alert.informativeText = "Use it for “\(newOwner)” instead? \(oldOwner) will no longer have a hotkey."
        alert.addButton(withTitle: "Use for \(newOwner)")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            KeyboardShortcuts.setShortcut(nil, for: conflict.other)
        } else {
            KeyboardShortcuts.setShortcut(conflict.previous, for: conflict.name)
        }
    }

    private func rebuildBindings() {
        var result: [KeyboardShortcuts.Shortcut: KeyboardShortcuts.Name] = [:]
        for name in actions.keys {
            if let shortcut = KeyboardShortcuts.getShortcut(for: name) {
                result[shortcut] = name
            }
        }
        bindings = result
        registerAll()
    }

    /// Replaces the system registrations with the current bindings (none while recording).
    private func registerAll() {
        for (_, hotkey) in registered { UnregisterEventHotKey(hotkey.ref) }
        registered = [:]
        guard !isRecording else { return }

        for (shortcut, name) in bindings {
            nextID &+= 1
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(
                UInt32(shortcut.carbonKeyCode),
                UInt32(shortcut.carbonModifiers),
                EventHotKeyID(signature: Self.signature, id: nextID),
                GetApplicationEventTarget(),
                0,
                &ref
            )
            if status == noErr, let ref {
                registered[nextID] = (name, ref)
            } else {
                log.info("could not register \(shortcut, privacy: .public) for \(name.rawValue, privacy: .public): \(status)")
            }
        }
    }

    /// "SKey", identifying Shortkeys' hotkeys in hotkey events.
    nonisolated fileprivate static let signature: OSType = 0x534B_6579

    /// Returns false if the ID isn't one of ours.
    fileprivate func pressed(id: UInt32) -> Bool {
        guard let name = registered[id]?.name, let action = actions[name] else { return false }
        // Run after the event handler returns, so the event isn't held up.
        Task { @MainActor in action() }
        return true
    }
}

private func hotkeyPressed(
    _ handler: EventHandlerCallRef?, _ event: EventRef?, _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    var id = EventHotKeyID()
    let status = GetEventParameter(
        event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
        nil, MemoryLayout<EventHotKeyID>.size, nil, &id
    )
    guard status == noErr, id.signature == HotkeyCenter.signature else { return OSStatus(eventNotHandledErr) }
    // Carbon events are dispatched on the main thread.
    let handled = MainActor.assumeIsolated { HotkeyCenter.shared.pressed(id: id.id) }
    return handled ? noErr : OSStatus(eventNotHandledErr)
}
