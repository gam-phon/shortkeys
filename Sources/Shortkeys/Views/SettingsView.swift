import Observation
import SwiftUI

@MainActor
@Observable
final class SettingsModel {
    static let shared = SettingsModel()

    enum Page: String, CaseIterable, Identifiable {
        case general, apps, windows, about
        var id: Self { self }

        var title: String {
            switch self {
            case .general: "General"
            case .apps: "Apps"
            case .windows: "Window Management"
            case .about: "About"
            }
        }

        var icon: SidebarIcon {
            switch self {
            case .general: SidebarIcon(systemName: "gearshape.fill", color: .gray)
            case .apps: SidebarIcon(systemName: "square.grid.2x2.fill", color: .blue)
            case .windows: SidebarIcon(systemName: "macwindow", color: .indigo)
            case .about: SidebarIcon(systemName: "info", color: .gray)
            }
        }
    }

    var page: Page? = .general
}

struct SettingsView: View {
    static let windowID = "settings"

    @Bindable private var model = SettingsModel.shared

    var body: some View {
        // Like System Settings, the sidebar is always shown. Collapsing it made
        // the page jump: AppKit slides the sidebar in over the page, and
        // SwiftUI only re-lays out the page once the animation has finished.
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(SettingsModel.Page.allCases, selection: $model.page) { page in
                Label { Text(page.title) } icon: { page.icon }
                    .tag(page)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            Group {
                switch model.page ?? .general {
                case .general: GeneralPage()
                case .apps: AppsPage()
                case .windows: WindowManagementPage()
                case .about: AboutPage()
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) { StatusBanner() }
            // Let the page run under the title bar, as in System Settings,
            // instead of a separate toolbar band with a hard edge and separator.
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        }
        .frame(minWidth: 680, minHeight: 460)
        .onAppear {
            DockIcon.show()
            Permissions.shared.refresh()
            LaunchAtLogin.shared.refresh()
        }
        .onDisappear { DockIcon.hide() }
    }
}

/// Explains why hotkeys aren't working, if something is blocking them.
private struct StatusBanner: View {
    private var status = Permissions.shared

    var body: some View {
        VStack(spacing: 0) {
            if !status.isTrusted {
                banner(
                    title: "Accessibility access is off",
                    message: "Hotkeys and window commands won't work until Shortkeys is turned on in Privacy & Security → Accessibility.",
                    action: ("Open System Settings", { status.openSystemSettings() })
                )
            }
            if let holder = status.secureInputHolder {
                banner(
                    title: "Hotkeys are paused by Secure Keyboard Entry",
                    message: holder == "loginwindow"
                        ? "macOS left secure input on after unlocking. Lock and unlock the screen, or log out and back in."
                        : "\(holder) has secure input on (usually a password field or a terminal setting). Hotkeys resume when it's turned off.",
                    action: nil
                )
            }
        }
    }

    private func banner(title: String, message: String, action: (String, () -> Void)?) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(message).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if let action {
                Button(action.0, action: action.1)
            }
        }
        .padding(12)
        .background(.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding([.horizontal, .top], 16)
        .padding(.bottom, 4)
    }
}

/// Opens the settings window from outside SwiftUI views (the app delegate,
/// the menu). SwiftUI's `openWindow` action is captured from the menu bar
/// label, which exists for the whole lifetime of the app.
@MainActor
enum SettingsWindow {
    static var openWindow: OpenWindowAction?

    /// Brings Shortkeys to the front with Settings open.
    ///
    /// `NSApp.activate()` is cooperative and is declined while
    /// another app is in front, which is always the case for a menu bar app.
    /// Opening ourselves through LaunchServices activates the app, like
    /// clicking it in Finder, and delivers a reopen event that calls `show()`.
    static func open() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            if let error {
                log.error("activating Shortkeys failed: \(error.localizedDescription, privacy: .public)")
                Task { @MainActor in show() }
            }
        }
    }

    /// Shows the window; called for the reopen event once Shortkeys is active.
    static func show() {
        DockIcon.show()
        openWindow?(id: SettingsView.windowID)
    }
}

/// Shortkeys normally has no Dock icon; it gets one while Settings is open so
/// the window shows up in ⌘-Tab.
@MainActor
enum DockIcon {
    private static var isObservingClose = false

    static func show() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()

        // Backup for `onDisappear`: hide again once no normal window is left.
        if !isObservingClose {
            isObservingClose = true
            NotificationCenter.default.observe(NSWindow.willCloseNotification) {
                // After the window has finished closing.
                Task {
                    let hasWindow = NSApp.windows.contains { $0.isVisible && $0.canBecomeMain }
                    if !hasWindow { DockIcon.hide() }
                }
            }
        }
    }

    static func hide() {
        NSApp.setActivationPolicy(.accessory)
    }
}
