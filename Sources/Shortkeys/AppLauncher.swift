import AppKit
import ApplicationServices

/// Launches an app, brings it to the front, or cycles its windows.
@MainActor
enum AppLauncher {
    static func trigger(bundleID: String) {
        let workspace = NSWorkspace.shared
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first { !$0.isTerminated }

        if let app = running, workspace.frontmostApplication?.processIdentifier == app.processIdentifier {
            if !cycleWindows(of: app) {
                open(bundleID: bundleID)
            }
            return
        }

        // Not running, or running in the background. Opening through
        // NSWorkspace activates the app, unhides it and sends a reopen event
        // (which creates a window if it has none), just like clicking it in the Dock.
        open(bundleID: bundleID)
    }

    private static func open(bundleID: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            log.error("no app found for \(bundleID, privacy: .public)")
            NSSound.beep()
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
            if let error {
                log.error("open \(bundleID, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Raises the app's back-most window, so repeated presses walk through
    /// all windows. Returns false if the app has no usable windows.
    private static func cycleWindows(of app: NSRunningApplication) -> Bool {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        let windows = AX.windows(of: axApp).filter { window in
            AX.string(window, kAXSubroleAttribute) == kAXStandardWindowSubrole as String
                && AX.bool(window, kAXMinimizedAttribute) != true
        }
        guard !windows.isEmpty else { return false }
        guard windows.count > 1, let target = windows.last else { return true }

        AXUIElementSetAttributeValue(target, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(target, kAXRaiseAction as CFString)
        return true
    }
}

/// Small helpers around the AXUIElement C API.
enum AX {
    static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        value(element, attribute) as? String
    }

    static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        (value(element, attribute) as? NSNumber)?.boolValue
    }

    static func windows(of app: AXUIElement) -> [AXUIElement] {
        (value(app, kAXWindowsAttribute) as? [AXUIElement]) ?? []
    }
}
