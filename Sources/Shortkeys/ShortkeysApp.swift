import KeyboardShortcuts
import SwiftUI

@main
struct ShortkeysApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(SettingsKey.showMenuBarIcon) private var showMenuBarIcon = true

    var body: some Scene {
        MenuBarExtra(isInserted: $showMenuBarIcon) {
            MenuContent()
        } label: {
            MenuBarIcon()
        }

        Window("Shortkeys Settings", id: SettingsView.windowID) {
            SettingsView()
        }
        .defaultSize(width: 780, height: 600)
        .windowResizability(.contentMinSize)
        .defaultLaunchBehavior(.suppressed) // a menu bar app: no window at launch
        .restorationBehavior(.disabled)
        .commands {
            // "Settings… ⌘," in the app menu while the Dock icon is shown. Its
            // view is also where `openWindow` is captured for code outside
            // SwiftUI; unlike the menu bar icon, it exists even when the icon is hidden.
            CommandGroup(replacing: .appSettings) {
                SettingsCommand()
            }
        }
    }
}

private struct SettingsCommand: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let _ = SettingsWindow.openWindow = openWindow
        Button("Settings…") { SettingsWindow.show() }
            .keyboardShortcut(",")
    }
}

private struct MenuBarIcon: View {
    private var status = Permissions.shared

    var body: some View {
        Image(systemName: status.hotkeysBlocked ? "exclamationmark.triangle" : "command")
    }
}

private struct MenuContent: View {
    private var status = Permissions.shared
    private var updater = Updater.shared

    var body: some View {
        if let release = updater.availableRelease {
            Button("Update to Shortkeys \(release.version)…") {
                SettingsModel.shared.page = .general
                SettingsWindow.open()
            }
            Divider()
        }
        if !status.isTrusted {
            Button("⚠︎ Grant Accessibility Access…") { status.openSystemSettings() }
            Divider()
        } else if let holder = status.secureInputHolder {
            Text("⚠︎ Hotkeys paused: secure input on (\(holder))")
            Divider()
        }
        Button("Open Settings…") { SettingsWindow.open() }
            .keyboardShortcut(",")
        Divider()
        Button("Quit Shortkeys") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Shortkeys has no windows most of the time (and no menu bar icon if the
        // user hides it), which makes it a candidate for automatic termination.
        // Its hotkeys must keep working, so opt out.
        ProcessInfo.processInfo.disableAutomaticTermination("Shortkeys listens for global hotkeys")
        // Always start Settings with the standard sidebar width.
        UserDefaults.standard.removeObject(forKey: SettingsView.splitViewAutosaveKey)
        // Before any shortcut name is created: Shortkeys delivers hotkeys
        // itself (HotkeyCenter), so KeyboardShortcuts must not register them.
        KeyboardShortcuts.isEnabled = false
        AppHotkeys.shared.start()
        for command in WindowCommand.allCases {
            HotkeyCenter.shared.register(command.shortcutName) {
                WindowManager.shared.perform(command)
            }
        }
        if ProcessInfo.processInfo.arguments.contains("--uninstall") {
            Uninstaller.uninstall()
            return
        }
        if Snapshot.isRequested {
            // Self-tests run unattended (also in CI, without Accessibility access).
            Snapshot.runIfRequested()
        } else if ProcessInfo.processInfo.arguments.contains("--update-test") {
            // Developer test: install the latest release even if it isn't newer.
            Task {
                do {
                    let release = try await Updater.fetchLatestRelease()
                    log.info("update test: installing \(release.version, privacy: .public)")
                    await Updater.shared.install(release)
                    if case .failed(let message) = Updater.shared.state {
                        log.error("update test failed: \(message, privacy: .public)")
                        NSApp.terminate(nil)
                    }
                } catch {
                    log.error("update test failed: \(error.localizedDescription, privacy: .public)")
                    NSApp.terminate(nil)
                }
            }
        } else {
            Permissions.shared.promptIfNeeded()
            if UserDefaults.standard.object(forKey: SettingsKey.checkForUpdates) as? Bool ?? true {
                Task { await Updater.shared.checkIfDue() }
            }
        }
    }

    /// A menu bar app keeps running with no windows. SwiftUI doesn't set this
    /// for `MenuBarExtra(isInserted:)`, and closing the status menu or Settings
    /// then quit Shortkeys.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Opening Shortkeys again (Finder, Spotlight, Launchpad) shows Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        SettingsWindow.show()
        return false
    }
}
