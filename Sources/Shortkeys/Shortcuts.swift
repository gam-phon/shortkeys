import AppKit
import KeyboardShortcuts
import os

let log = Logger(subsystem: "com.yaser.shortkeys", category: "main")

/// Keeps track of which apps have a launch hotkey and wires their handlers.
///
/// Each app gets a dynamic shortcut name `app:<bundleID>`. KeyboardShortcuts
/// stores the key combination; we only store the list of bundle IDs that
/// have one, so handlers can be registered at launch without scanning disks.
@MainActor
final class AppHotkeys {
    static let shared = AppHotkeys()

    static let defaultShortcuts: [String: KeyboardShortcuts.Shortcut] = [
        "org.mozilla.firefox": .init(.b, modifiers: [.control, .option]),
        "com.mitchellh.ghostty": .init(.t, modifiers: [.control, .option]),
        "com.anthropic.claudefordesktop": .init(.g, modifiers: [.control, .option]),
        "com.apple.Notes": .init(.n, modifiers: [.control, .option]),
    ]

    /// Defaults before 1.4.0. A hotkey still on one of these moves to the new default, once.
    static let oldDefaultShortcuts: [String: KeyboardShortcuts.Shortcut] = [
        "org.mozilla.firefox": .init(.b, modifiers: .option),
        "com.mitchellh.ghostty": .init(.t, modifiers: .option),
        "com.anthropic.claudefordesktop": .init(.g, modifiers: .option),
        "com.apple.Notes": .init(.n, modifiers: .option),
    ]

    private let registryKey = "appShortcutIDs"
    let movedDefaultsKey = "movedToControlOptionDefaults"
    private var attached = Set<String>()

    static func name(for bundleID: String) -> KeyboardShortcuts.Name {
        KeyboardShortcuts.Name("app:\(bundleID)", default: defaultShortcuts[bundleID])
    }

    /// Bundle IDs that currently have (or had) a shortcut assigned.
    var bundleIDs: Set<String> {
        get {
            if let stored = UserDefaults.standard.stringArray(forKey: registryKey) {
                return Set(stored)
            }
            return Set(Self.defaultShortcuts.keys)
        }
        set { UserDefaults.standard.set(newValue.sorted(), forKey: registryKey) }
    }

    func start() {
        moveOldDefaults()
        for id in bundleIDs { attach(id) }

        // Any recorder change; app shortcuts are the ones named "app:<bundleID>".
        NotificationCenter.default.observe(.shortcutDidChange, value: \.shortcutName) { name in
            guard let name, name.rawValue.hasPrefix("app:") else { return }
            AppHotkeys.shared.shortcutChanged(bundleID: String(name.rawValue.dropFirst("app:".count)))
        }
    }

    /// Moves hotkeys the user never changed from the old ⌥ defaults to the new
    /// ⌃⌥ ones. Runs once; skips a new hotkey that something else already uses.
    func moveOldDefaults() {
        guard !UserDefaults.standard.bool(forKey: movedDefaultsKey) else { return }
        UserDefaults.standard.set(true, forKey: movedDefaultsKey)
        var taken = Set(bundleIDs.compactMap { KeyboardShortcuts.getShortcut(for: Self.name(for: $0)) })
        taken.formUnion(WindowCommand.allCases.compactMap { KeyboardShortcuts.getShortcut(for: $0.shortcutName) })
        for (id, old) in Self.oldDefaultShortcuts {
            let name = Self.name(for: id)
            guard
                KeyboardShortcuts.getShortcut(for: name) == old,
                let new = Self.defaultShortcuts[id],
                !taken.contains(new)
            else { continue }
            KeyboardShortcuts.setShortcut(new, for: name)
            taken.insert(new)
            log.info("moved \(id, privacy: .public) from \(old, privacy: .public) to \(new, privacy: .public)")
        }
    }

    func hasShortcut(_ bundleID: String) -> Bool {
        KeyboardShortcuts.getShortcut(for: Self.name(for: bundleID)) != nil
    }

    private func shortcutChanged(bundleID: String) {
        var ids = bundleIDs
        if hasShortcut(bundleID) {
            ids.insert(bundleID)
            attach(bundleID)
        } else {
            ids.remove(bundleID)
        }
        bundleIDs = ids
    }

    private func attach(_ bundleID: String) {
        guard attached.insert(bundleID).inserted else { return }
        let name = Self.name(for: bundleID)
        HotkeyCenter.shared.register(name) {
            AppLauncher.trigger(bundleID: bundleID)
        }
    }
}

extension KeyboardShortcuts.Name {
    /// What this hotkey is for, as shown to the user: an app's name or a window command.
    var title: String {
        if rawValue.hasPrefix("app:") {
            let bundleID = String(rawValue.dropFirst("app:".count))
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
            return url.deletingPathExtension().lastPathComponent
        }
        if rawValue.hasPrefix("window:"), let command = WindowCommand(rawValue: String(rawValue.dropFirst("window:".count))) {
            return command.title
        }
        return rawValue
    }
}
