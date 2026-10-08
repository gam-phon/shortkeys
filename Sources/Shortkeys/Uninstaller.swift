import AppKit
import ServiceManagement

/// Removes Shortkeys from this Mac: its login item, settings, Accessibility
/// entry, and the app itself (moved to the Trash, so it can be recovered).
@MainActor
enum Uninstaller {
    /// Asks first; used by the button in Settings → General.
    static func confirmAndUninstall() {
        NSApp.activate()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Uninstall Shortkeys?"
        alert.informativeText = """
            This turns off Launch at Login, deletes your hotkeys and settings, removes \
            Shortkeys from Accessibility, and moves the app to the Trash.
            """
        let uninstallButton = alert.addButton(withTitle: "Uninstall")
        uninstallButton.hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        uninstall()
    }

    /// Removes everything, then quits. Also run by `Shortkeys --uninstall`.
    static func uninstall() {
        try? SMAppService.mainApp.unregister()

        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
            // An app may reset its own Accessibility entry; no admin rights needed.
            let tccutil = Process()
            tccutil.executableURL = URL(filePath: "/usr/bin/tccutil")
            tccutil.arguments = ["reset", "Accessibility", bundleID]
            try? tccutil.run()
            tccutil.waitUntilExit()
        }

        let app = Bundle.main.bundleURL
        NSWorkspace.shared.recycle([app]) { _, error in
            if let error {
                log.error("moving Shortkeys to the Trash failed: \(error.localizedDescription, privacy: .public)")
            }
            Task { @MainActor in
                // Write after the settings domain was removed, and don't save it again.
                UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier ?? "")
                NSApp.terminate(nil)
            }
        }
    }
}
