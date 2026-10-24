import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Observation

/// Tracks what can stop Shortkeys from working: a missing Accessibility grant
/// (needed to move windows and switch between them), or another process
/// holding Secure Keyboard Entry (macOS then blocks ⌥-only hotkeys). Refreshed
/// on system events, and every few seconds while Accessibility is off.
@MainActor
@Observable
final class Permissions {
    static let shared = Permissions()

    private(set) var isTrusted = AXIsProcessTrusted()
    /// Name of the process holding secure input, or nil when it's off.
    private(set) var secureInputHolder: String?

    var hotkeysBlocked: Bool {
        !isTrusted || (secureInputHolder != nil && !HotkeyCenter.shared.blockedBySecureInput.isEmpty)
    }

    private var isPolling = false

    private init() {
        NotificationCenter.default.observe(NSApplication.didBecomeActiveNotification) {
            Permissions.shared.refreshSoon()
        }
        // Opening the menu bar menu.
        NotificationCenter.default.observe(NSMenu.didBeginTrackingNotification) {
            Permissions.shared.refreshSoon()
        }
        NSWorkspace.shared.notificationCenter.observe(NSWorkspace.didWakeNotification) {
            Permissions.shared.refreshSoon()
        }
        // The Accessibility list changed, or the screen was unlocked (when
        // loginwindow sometimes keeps secure input on by mistake).
        for name in ["com.apple.accessibility.api", "com.apple.screenIsUnlocked"] {
            DistributedNotificationCenter.default().observe(.init(name)) {
                Permissions.shared.refreshSoon()
            }
        }
    }

    /// The system state settles shortly after these notifications.
    private func refreshSoon() {
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            refresh()
        }
    }

    func refresh() {
        isTrusted = AXIsProcessTrusted()
        secureInputHolder = SecureInput.holder()
        if !isTrusted { pollUntilTrusted() }
    }

    /// The "accessibility changed" notification doesn't always arrive, and right
    /// after an update the grant can lag for a moment, so check until it's on.
    private func pollUntilTrusted() {
        guard !isPolling else { return }
        isPolling = true
        Task {
            while !AXIsProcessTrusted() {
                try? await Task.sleep(for: .seconds(2))
            }
            isPolling = false
            refresh()
        }
    }

    func openSystemSettings() {
        // System Settings (macOS 13+) pane ID; the old com.apple.preference.security ID can land on the wrong page.
        let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    /// Asks macOS for Accessibility access: adds Shortkeys to the list and
    /// offers to open System Settings. The key is `kAXTrustedCheckOptionPrompt`'s value.
    func requestAccess() {
        refresh()
        guard !isTrusted else { return }
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    /// Shown once at launch if the permission is missing.
    func promptIfNeeded() {
        refresh()
        guard !isTrusted else { return }

        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Shortkeys needs Accessibility access"
        alert.informativeText = """
            Shortkeys moves and resizes windows, and switches between an app's \
            windows. macOS only allows this for apps you turn on in \
            System Settings → Privacy & Security → Accessibility \
            (called "Device Control and Data Access" on newer macOS).

            Next, macOS asks you to allow it. Turn on Shortkeys there and window \
            hotkeys start working right away. App hotkeys work without it.
            """
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            requestAccess()
        }
    }
}

enum SecureInput {
    /// The name of the process that has Secure Keyboard Entry on, or nil.
    static func holder() -> String? {
        guard IsSecureEventInputEnabled() else { return nil }
        guard let pid = holderPID() else { return "Another app" }
        if let name = NSRunningApplication(processIdentifier: pid)?.localizedName {
            return name
        }
        var buffer = [UInt8](repeating: 0, count: 256)
        proc_name(pid, &buffer, UInt32(buffer.count))
        let name = String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
        return name.isEmpty ? "Another app" : name
    }

    /// Read from the console user entry in the I/O Registry (what `ioreg` shows).
    private static func holderPID() -> pid_t? {
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        defer { IOObjectRelease(root) }
        guard
            let users = IORegistryEntryCreateCFProperty(root, "IOConsoleUsers" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [[String: Any]]
        else { return nil }
        for user in users {
            if let pid = user["kCGSSessionSecureInputPID"] as? Int {
                return pid_t(pid)
            }
        }
        return nil
    }
}
