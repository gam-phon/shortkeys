import SwiftUI

struct GeneralPage: View {
    @Bindable private var launchAtLogin = LaunchAtLogin.shared
    @AppStorage(SettingsKey.showMenuBarIcon) private var showMenuBarIcon = true
    private var permissions = Permissions.shared

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
            }
            .padding(20)
        }
        .navigationTitle("General")
        .task { launchAtLogin.refresh() }
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
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            control
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(.vertical, 8)
    }
}
