import Observation
import ServiceManagement

@MainActor
@Observable
final class LaunchAtLogin {
    static let shared = LaunchAtLogin()

    /// On when Shortkeys is registered as a login item, even if macOS still
    /// waits for the user to approve it.
    var isEnabled = LaunchAtLogin.isRegistered {
        didSet {
            guard isEnabled != Self.isRegistered else { return }
            do {
                if isEnabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                log.error("launch at login change failed: \(error.localizedDescription, privacy: .public)")
            }
            refresh()
        }
    }

    /// macOS registered the login item but the user has to allow it in
    /// System Settings → General → Login Items.
    private(set) var needsApproval = SMAppService.mainApp.status == .requiresApproval

    /// The user can change this in System Settings, so re-read it when Settings opens.
    func refresh() {
        if isEnabled != Self.isRegistered { isEnabled = Self.isRegistered }
        needsApproval = SMAppService.mainApp.status == .requiresApproval
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private static var isRegistered: Bool {
        [.enabled, .requiresApproval].contains(SMAppService.mainApp.status)
    }
}

/// Settings stored in UserDefaults (read with `@AppStorage`).
enum SettingsKey {
    /// Whether the ⌘ icon is shown in the menu bar.
    static let showMenuBarIcon = "showMenuBarIcon"
}
