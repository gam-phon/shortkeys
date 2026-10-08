import SwiftUI

struct GeneralPage: View {
    @Bindable private var launchAtLogin = LaunchAtLogin.shared
    @AppStorage(SettingsKey.showMenuBarIcon) private var showMenuBarIcon = true
    @AppStorage(SettingsKey.checkForUpdates) private var checkForUpdates = true
    @AppStorage(SettingsKey.installUpdatesAutomatically) private var installUpdatesAutomatically = true
    private var permissions = Permissions.shared
    private var updater = Updater.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SettingsGroup(title: "Startup") {
                    SettingRow("Launch at Login", detail: "Start Shortkeys automatically when you log in.") {
                        Toggle("Launch at Login", isOn: $launchAtLogin.isEnabled)
                    }
                    if launchAtLogin.needsApproval {
                        Divider()
                        SettingRow("Waiting for approval", detail: "Allow Shortkeys under Login Items in System Settings.") {
                            Button("Open Login Items…") { launchAtLogin.openLoginItemsSettings() }
                        }
                    }
                }

                SettingsGroup(title: "Updates") {
                    SettingRow("Shortkeys \(updater.currentVersion)", detail: updateStatus) {
                        updateControl
                    }
                    Divider()
                    SettingRow("Check for updates automatically", detail: "When Shortkeys starts, about once a day, and when you open Settings.") {
                        Toggle("Check for updates automatically", isOn: $checkForUpdates)
                    }
                    Divider()
                    SettingRow(
                        "Install updates automatically",
                        detail: "Installs when the Mac hasn't been used for 5 minutes, or when Shortkeys starts. The previous version goes to the Trash."
                    ) {
                        Toggle("Install updates automatically", isOn: $installUpdatesAutomatically)
                            .disabled(!checkForUpdates)
                    }
                }

                SettingsGroup(
                    title: "Menu Bar",
                    footer: "When the icon is hidden, open Shortkeys again from Spotlight or the Applications folder to show this window."
                ) {
                    SettingRow("Show in menu bar", detail: "The ⌘ icon gives quick access to Settings and Quit.") {
                        Toggle("Show in menu bar", isOn: $showMenuBarIcon)
                    }
                }

                SettingsGroup(title: "Permissions") {
                    SettingRow(
                        "Accessibility",
                        detail: "Needed to detect hotkeys, switch between an app's windows, and move and resize windows."
                    ) {
                        if permissions.isTrusted {
                            Label("Allowed", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Button("Open System Settings…") { permissions.openSystemSettings() }
                        }
                    }
                }

                SettingsGroup(title: "Uninstall") {
                    SettingRow(
                        "Uninstall Shortkeys",
                        detail: "Removes the login item, your hotkeys and settings, and the Accessibility entry, and moves the app to the Trash."
                    ) {
                        Button("Uninstall…", role: .destructive) { Uninstaller.confirmAndUninstall() }
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle("General")
        .task {
            launchAtLogin.refresh()
            if checkForUpdates { await updater.checkIfDue() }
        }
    }

    private var updateStatus: String {
        switch updater.state {
        case .idle, .upToDate, .checking:
            if let from = updater.updatedFrom {
                "Updated from \(from). The previous version is in the Trash, if you need it back."
            } else if updater.state == .checking {
                "Checking for updates…"
            } else if updater.state == .upToDate {
                "You're using the latest version."
            } else {
                "Check GitHub for a newer version."
            }
        case .available(let release): "Version \(release.version) is available. It installs and restarts Shortkeys; your hotkeys and settings are kept."
        case .downloading: "Downloading and verifying the update…"
        case .installing: "Installing… Shortkeys will restart."
        case .failed(let message): message
        }
    }

    @ViewBuilder private var updateControl: some View {
        if updater.isBusy {
            ProgressView().controlSize(.small)
        } else if let release = updater.availableRelease {
            HStack {
                Link("What's New", destination: release.pageURL)
                Button("Update to \(release.version)") { Task { await updater.install(release) } }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            Button("Check Now") { Task { await updater.check() } }
        }
    }
}

/// A settings row: title and explanation on the left, a control on the right.
private struct SettingRow<Control: View>: View {
    let title: String
    let detail: String
    @ViewBuilder let control: Control

    init(_ title: String, detail: String, @ViewBuilder control: () -> Control) {
        self.title = title
        self.detail = detail
        self.control = control()
    }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            control
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(.vertical, 8)
    }
}
