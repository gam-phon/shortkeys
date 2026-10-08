import AppKit
import KeyboardShortcuts

/// Delivers global hotkeys through a CGEvent tap.
///
/// KeyboardShortcuts still stores shortcuts and provides the recorder, but its
/// Carbon `RegisterEventHotKey` backend does not receive key presses on this
/// macOS version, so we match key-down events ourselves. The tap needs the
/// Accessibility permission and is created as soon as that is granted.
@MainActor
final class HotkeyCenter {
    static let shared = HotkeyCenter()

    private var actions: [KeyboardShortcuts.Name: @MainActor @Sendable () -> Void] = [:]
    private var bindings: [KeyboardShortcuts.Shortcut: KeyboardShortcuts.Name] = [:]
    private var tap: CFMachPort?
    private var isRecording = false

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
        NotificationCenter.default.observe(.shortcutDidChange, value: \.shortcutName) { name in
            HotkeyCenter.shared.shortcutChanged(name)
        }
        // Don't trigger actions while the user is recording a new shortcut.
        NotificationCenter.default.observe(.recorderActiveDidChange, value: \.isRecorderActive) { isActive in
            HotkeyCenter.shared.isRecording = isActive
        }
    }

    func register(_ name: KeyboardShortcuts.Name, action: @escaping @MainActor @Sendable () -> Void) {
        actions[name] = action
        rebuildBindings()
        startIfPossible()
    }

    /// Creates the event tap if it doesn't exist yet. Safe to call repeatedly.
    func startIfPossible() {
        guard tap == nil else { return }
        guard AXIsProcessTrusted() else {
            log.info("event tap waiting for Accessibility permission")
            return
        }

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: hotkeyTapCallback,
            userInfo: nil
        ) else {
            log.error("could not create event tap")
            return
        }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        log.info("event tap started")
    }

    /// Whether a recorder is capturing a new shortcut (hotkeys are paused meanwhile).
    var isRecordingShortcut: Bool { isRecording }

    /// The action name a key combination would trigger (used by the self-test).
    func binding(for shortcut: KeyboardShortcuts.Shortcut) -> KeyboardShortcuts.Name? {
        bindings[shortcut]
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
    }

    /// Returns true if the event matched a hotkey and should be swallowed.
    fileprivate func handle(keyCode: Int64, flags: CGEventFlags, isRepeat: Bool) -> Bool {
        guard !isRecording else { return false }

        var modifiers: NSEvent.ModifierFlags = []
        if flags.contains(.maskCommand) { modifiers.insert(.command) }
        if flags.contains(.maskAlternate) { modifiers.insert(.option) }
        if flags.contains(.maskControl) { modifiers.insert(.control) }
        if flags.contains(.maskShift) { modifiers.insert(.shift) }

        let shortcut = KeyboardShortcuts.Shortcut(KeyboardShortcuts.Key(rawValue: Int(keyCode)), modifiers: modifiers)
        guard let name = bindings[shortcut], let action = actions[name] else { return false }

        // Swallow auto-repeat so holding the keys doesn't re-trigger, but still
        // don't let them through to the focused app.
        if !isRepeat {
            // Run after the tap callback returns, so the event isn't held up.
            Task { @MainActor in action() }
        }
        return true
    }

    fileprivate func reenable() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }
}

private func hotkeyTapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    // The tap's run loop source is on the main run loop, so this runs on the
    // main thread. Only plain values cross into the main actor, not the event.
    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        MainActor.assumeIsolated { HotkeyCenter.shared.reenable() }
    case .keyDown:
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        let swallow = MainActor.assumeIsolated {
            HotkeyCenter.shared.handle(keyCode: keyCode, flags: flags, isRepeat: isRepeat)
        }
        if swallow { return nil }
    default:
        break
    }
    return Unmanaged.passUnretained(event)
}
