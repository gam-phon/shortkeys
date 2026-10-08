import AppKit
import KeyboardShortcuts

/// Developer self-tests, run only when the app is launched with an argument:
///
/// - `open Shortkeys.app --args --snapshot <folder>`: opens Settings, saves a
///   PNG of each page (no Screen Recording permission needed) and writes
///   `selftest.txt`, a check of the hotkey wiring. Presses no keys.
/// - `open Shortkeys.app --args --e2e-test <folder>`: drives the real UI with
///   synthetic input, like a user: click the menu bar icon, choose Open
///   Settings… (⌘,), click a recorder, press ⌥N. Writes `e2e.txt` and restores
///   the shortcuts it touched.
@MainActor
enum Snapshot {
    /// Whether the app was launched to run a self-test (it quits when done).
    static var isRequested: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("--snapshot") || arguments.contains("--e2e-test")
    }

    static func runIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        let tests: [(String, @MainActor (URL) async -> Void)] = [
            ("--snapshot", snapshots(into:)),
            ("--e2e-test", endToEnd(into:)),
        ]
        for (flag, run) in tests {
            guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { continue }
            let folder = URL(filePath: arguments[index + 1])
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1)) // let the app finish launching
                await run(folder)
                NSApp.terminate(nil)
            }
        }
    }

    // MARK: - Snapshots and wiring self-test

    private static func snapshots(into folder: URL) async {
        let settings = SettingsModel.shared
        let catalog = AppCatalog.shared
        settings.page = .general
        SettingsWindow.show()
        try? await Task.sleep(for: .seconds(1))
        save("0-general", to: folder)

        settings.page = .apps
        try? await Task.sleep(for: .seconds(2)) // app list loads in the background
        save("1-apps", to: folder)

        catalog.search = "fire"
        try? await Task.sleep(for: .seconds(1))
        save("2-apps-search", to: folder)

        catalog.search = ""
        catalog.filter = .withShortcuts
        try? await Task.sleep(for: .seconds(1))
        save("3-apps-with-shortcuts", to: folder)

        catalog.filter = .all
        settings.page = .windows
        try? await Task.sleep(for: .seconds(1))
        save("4-window-management", to: folder)

        let windows = WindowCommandsModel.shared
        windows.filter = .withShortcuts
        try? await Task.sleep(for: .seconds(1))
        save("4b-window-management-with-shortcuts", to: folder)
        windows.filter = .all
        windows.search = "third"
        try? await Task.sleep(for: .seconds(1))
        save("4c-window-management-search", to: folder)
        windows.search = ""
        settings.page = .apps

        settings.page = .about
        try? await Task.sleep(for: .seconds(1))
        save("4d-about", to: folder)
        settings.page = .apps

        // Smallest allowed window: toolbar and rows must not overlap.
        if let window = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }) {
            let original = window.frame
            window.setContentSize(window.contentMinSize)
            catalog.search = "Notes"
            try? await Task.sleep(for: .seconds(1))
            save("5-apps-narrow", to: folder)
            catalog.search = ""
            window.setFrame(original, display: true)
        }

        write(await wiringSelfTest(), to: folder.appending(path: "selftest.txt"))
        NSApp.windows.first { $0.isVisible && $0.canBecomeMain }?.performClose(nil)
    }

    /// Records a hotkey for Calculator the way the recorder does, checks that
    /// the event tap would match it, then removes it. Presses no keys.
    private static func wiringSelfTest() async -> [String] {
        var lines: [String] = []
        func check(_ label: String, _ ok: Bool) { lines.append("\(ok ? "ok  " : "FAIL") \(label)") }

        let bundleID = "com.apple.calculator"
        let name = AppHotkeys.name(for: bundleID)
        let shortcut = KeyboardShortcuts.Shortcut(.f19, modifiers: [.control, .option, .command])
        let before = KeyboardShortcuts.getShortcut(for: name)

        KeyboardShortcuts.setShortcut(shortcut, for: name)
        check("recorded hotkey is stored", KeyboardShortcuts.getShortcut(for: name) == shortcut)
        check("app is added to the hotkey registry", AppHotkeys.shared.bundleIDs.contains(bundleID))
        check("event tap matches the new hotkey immediately", HotkeyCenter.shared.binding(for: shortcut) == name)
        check("'With shortcuts only' includes the app", AppHotkeys.shared.hasShortcut(bundleID))

        KeyboardShortcuts.setShortcut(before, for: name)
        check("cleared hotkey no longer matches", HotkeyCenter.shared.binding(for: shortcut) == nil)
        check("app is removed from the registry", !AppHotkeys.shared.bundleIDs.contains(bundleID))

        for command in WindowCommand.allCases {
            if let windowShortcut = KeyboardShortcuts.getShortcut(for: command.shortcutName) {
                check("\(command.title) hotkey is bound", HotkeyCenter.shared.binding(for: windowShortcut) == command.shortcutName)
            }
        }
        for (id, appShortcut) in AppHotkeys.defaultShortcuts {
            check("\(id) hotkey is bound", HotkeyCenter.shared.binding(for: appShortcut) == AppHotkeys.name(for: id))
        }
        // Reusing a hotkey: recording Firefox's ⌥B for Calculator is a conflict.
        let firefox = AppHotkeys.name(for: "org.mozilla.firefox")
        if let firefoxShortcut = KeyboardShortcuts.getShortcut(for: firefox) {
            var conflicts: [HotkeyCenter.Conflict] = []
            let askUser = HotkeyCenter.shared.onConflict
            HotkeyCenter.shared.onConflict = { conflicts.append($0) }
            KeyboardShortcuts.setShortcut(firefoxShortcut, for: name)
            await Task.yield()
            check("reusing Firefox's hotkey is reported as a conflict", conflicts.first?.other == firefox && conflicts.first?.name == name)
            KeyboardShortcuts.setShortcut(before, for: name)
            HotkeyCenter.shared.onConflict = askUser
            check("Firefox keeps its hotkey", KeyboardShortcuts.getShortcut(for: firefox) == firefoxShortcut)
        }
        check("Carbon backend is disabled", !KeyboardShortcuts.isEnabled)
        return lines
    }

    // MARK: - End-to-end test with synthetic input

    private static func endToEnd(into folder: URL) async {
        var lines: [String] = []
        let targets: [(SettingsModel.Page, KeyboardShortcuts.Name)] = [
            (.apps, AppHotkeys.name(for: "com.apple.Notes")),
            (.windows, WindowCommand.leftHalf.shortcutName),
        ]
        for (page, name) in targets {
            let saved = KeyboardShortcuts.getShortcut(for: name)
            var steps: [String] = []
            let recorded = await recordThroughUI(page: page, name: name, steps: &steps)
            lines += steps.map { "     \(page.title): \($0)" }
            KeyboardShortcuts.setShortcut(saved, for: name)
            let ok = recorded == KeyboardShortcuts.Shortcut(.n, modifiers: .option)
            lines.append("\(ok ? "ok  " : "FAIL") \(page.title): click recorder, press ⌥N → \(recorded.map { "\($0)" } ?? "nothing recorded")")
            lines.append("\(KeyboardShortcuts.getShortcut(for: name) == saved ? "ok  " : "FAIL") \(page.title): original hotkey restored")
            lines.append("\(HotkeyCenter.shared.isRecordingShortcut ? "FAIL" : "ok  ") \(page.title): hotkeys active again after recording")
        }
        write(lines, to: folder.appending(path: "e2e.txt"))
    }

    private static func recordThroughUI(
        page: SettingsModel.Page, name: KeyboardShortcuts.Name, steps: inout [String]
    ) async -> KeyboardShortcuts.Shortcut? {
        func note(_ text: String) {
            steps.append(text)
            log.info("e2e: \(text, privacy: .public)")
        }
        func state() -> String {
            let front = NSWorkspace.shared.frontmostApplication?.localizedName ?? "-"
            return "frontmost=\(front) active=\(NSApp.isActive) key=\(NSApp.keyWindow?.title ?? "none")"
        }
        if let statusWindow = NSApp.windows.first(where: { "\(type(of: $0))".contains("StatusBar") }),
           statusWindow.frame.height > 0 {
            // Menu bar icon → Open Settings… (its ⌘, key equivalent).
            click(at: CGPoint(x: statusWindow.frame.midX, y: statusWindow.frame.midY))
            try? await Task.sleep(for: .seconds(0.8))
            note("menu open: \(NSApp.windows.contains { "\(type(of: $0))".contains("Menu") && $0.isVisible })")
            postKey(43, flags: .maskCommand)
        } else {
            // The menu bar icon is hidden: open Shortkeys again, as the user would.
            note("menu bar icon hidden; reopening the app instead")
            SettingsWindow.open()
        }
        try? await Task.sleep(for: .seconds(1.5))
        note("after Open Settings…: \(state())")

        SettingsModel.shared.page = page
        AppCatalog.shared.filter = .all
        AppCatalog.shared.search = page == .apps ? "Notes" : ""
        try? await Task.sleep(for: .seconds(1))
        defer { AppCatalog.shared.search = "" }

        guard
            let window = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }),
            let recorder = findRecorder(in: window.contentView, for: name)
        else {
            note("settings window or recorder not found")
            return nil
        }
        let frame = window.convertToScreen(recorder.convert(recorder.bounds, to: nil))
        click(at: CGPoint(x: frame.midX, y: frame.midY))
        try? await Task.sleep(for: .seconds(0.5))
        let focused = (window.firstResponder as? NSView)?.isDescendant(of: recorder) == true || window.firstResponder === recorder
        note("after clicking recorder: \(state()) recorderFocused=\(focused)")
        postKey(45, flags: .maskAlternate) // ⌥N
        try? await Task.sleep(for: .seconds(0.7))
        let recorded = KeyboardShortcuts.getShortcut(for: name)
        window.performClose(nil)
        try? await Task.sleep(for: .seconds(0.5))
        return recorded
    }

    /// Clicks at a point in AppKit global coordinates.
    private static func click(at point: CGPoint) {
        let location = WindowGeometry.flip(
            CGRect(origin: point, size: .zero), primaryHeight: NSScreen.screens.first?.frame.maxY ?? 0
        ).origin
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: location, mouseButton: .left)?
                .post(tap: .cghidEventTap)
        }
    }

    private static func postKey(_ code: CGKeyCode, flags: CGEventFlags) {
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
    }

    private static func findRecorder(in view: NSView?, for name: KeyboardShortcuts.Name) -> NSView? {
        guard let view, !view.isHiddenOrHasHiddenAncestor else { return nil }
        if let recorder = view as? KeyboardShortcuts.RecorderCocoa, recorder.shortcutName == name {
            return recorder
        }
        for subview in view.subviews {
            if let found = findRecorder(in: subview, for: name) { return found }
        }
        return nil
    }

    // MARK: - Output

    private static func save(_ name: String, to folder: URL) {
        // The window's frame view, so the toolbar (search, filter) is included.
        guard
            let window = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }),
            let view = window.contentView?.superview,
            let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?
            .write(to: folder.appending(path: "\(name).png"))
    }

    private static func write(_ lines: [String], to url: URL) {
        try? (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}
