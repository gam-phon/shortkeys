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

        let bundleID = Bundle.main.bundleIdentifier ?? "com.yaser.shortkeys"
        UserDefaults.standard.removePersistentDomain(forName: bundleID)
        // An app may reset its own Accessibility entry; no admin rights needed.
        run("/usr/bin/tccutil", ["reset", "Accessibility", bundleID])

        // Caches macOS keeps for the app (URLSession downloads, window state).
        let library = URL.libraryDirectory
        for leftover in [
            library.appending(path: "HTTPStorages/\(bundleID)"),
            library.appending(path: "Caches/\(bundleID)"),
            library.appending(path: "Saved Application State/\(bundleID).savedState"),
        ] {
            try? FileManager.default.removeItem(at: leftover)
        }

        let app = Bundle.main.bundleURL
        NSWorkspace.shared.recycle([app]) { _, error in
            Task { @MainActor in
                if error != nil {
                    // Installed by the .pkg as root: moving it needs an admin password.
                    let trash = URL.homeDirectory.appending(path: ".Trash/Shortkeys.app")
                    let moved = AdminPrompt.run(
                        "mv -f \(AdminPrompt.quoted(Updater.plainPath(app))) \(AdminPrompt.quoted(Updater.plainPath(trash)))",
                        reason: "Shortkeys needs your password to move itself to the Trash."
                    )
                    if !moved {
                        log.error("moving Shortkeys to the Trash failed: \(error?.localizedDescription ?? "", privacy: .public)")
                    }
                }
                // Remove the settings once more and exit right away: SwiftUI writes
                // some settings while it runs and shuts down, which would recreate them.
                UserDefaults.standard.removePersistentDomain(forName: bundleID)
                exit(0)
            }
        }
    }

    private static func run(_ tool: String, _ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(filePath: tool)
        process.arguments = arguments
        try? process.run()
        process.waitUntilExit()
    }
}

/// Runs a shell command as administrator, after macOS's standard password prompt.
@MainActor
enum AdminPrompt {
    /// Returns whether the command ran and succeeded (false if the user cancelled).
    @discardableResult
    static func run(_ command: String, reason: String) -> Bool {
        let script = "do shell script \(appleScriptString(command)) with prompt \(appleScriptString(reason)) with administrator privileges"
        let osascript = Process()
        osascript.executableURL = URL(filePath: "/usr/bin/osascript")
        osascript.arguments = ["-e", script]
        do {
            try osascript.run()
        } catch {
            return false
        }
        osascript.waitUntilExit()
        return osascript.terminationStatus == 0
    }

    /// A path quoted for the shell.
    static func quoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func appleScriptString(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
