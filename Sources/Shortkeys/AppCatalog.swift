import AppKit
import KeyboardShortcuts
import Observation

/// The apps shown on the Apps settings page. Scanned once, off the main
/// actor, the first time the page appears.
@MainActor
@Observable
final class AppCatalog {
    static let shared = AppCatalog()

    struct Entry: Identifiable, Hashable, Sendable {
        let id: String // bundle identifier
        let name: String
        let url: URL
    }

    private(set) var entries: [Entry] = []
    private(set) var isLoading = false
    var search = ""
    var filter = ShortcutFilter.all
    /// Bumped when any shortcut changes, so the filtered list updates.
    private var shortcutRevision = 0

    @ObservationIgnored private var icons: [String: NSImage] = [:]

    private init() {
        NotificationCenter.default.observe(.shortcutDidChange) {
            AppCatalog.shared.shortcutRevision += 1
        }
    }

    var visible: [Entry] {
        _ = shortcutRevision
        let query = search.trimmingCharacters(in: .whitespaces)
        return entries.filter { entry in
            (query.isEmpty || entry.name.localizedCaseInsensitiveContains(query))
                && (filter == .all || AppHotkeys.shared.hasShortcut(entry.id))
        }
    }

    func icon(for entry: Entry) -> NSImage {
        if let icon = icons[entry.id] { return icon }
        let icon = NSWorkspace.shared.icon(forFile: entry.url.path(percentEncoded: false))
        icons[entry.id] = icon
        return icon
    }

    /// Called from the Apps page's `.task`; the scan runs off the main actor.
    func loadIfNeeded() async {
        guard entries.isEmpty, !isLoading else { return }
        isLoading = true
        entries = await Self.scan()
        isLoading = false
    }

    // MARK: - Scanning

    @concurrent
    private nonisolated static func scan() async -> [Entry] {
        let roots = [
            URL(filePath: "/Applications"),
            URL(filePath: "/System/Applications"),
            URL.homeDirectory.appending(path: "Applications"),
        ]
        var byID: [String: Entry] = [:]
        for root in roots {
            for url in appBundles(in: root, depth: 2) {
                guard let id = Bundle(url: url)?.bundleIdentifier, byID[id] == nil else { continue }
                // The name Finder shows: localized, without the ".app" extension.
                let name = (try? url.resourceValues(forKeys: [.localizedNameKey]).localizedName)
                    .map { $0.hasSuffix(".app") ? String($0.dropLast(4)) : $0 }
                    ?? url.deletingPathExtension().lastPathComponent
                byID[id] = Entry(id: id, name: name, url: url)
            }
        }
        return byID.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// `.app` bundles directly in `folder`, plus those in subfolders such as
    /// Utilities, without looking inside app bundles.
    private nonisolated static func appBundles(in folder: URL, depth: Int) -> [URL] {
        guard
            depth > 0,
            let children = try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        else { return [] }

        var result: [URL] = []
        for child in children {
            if child.pathExtension == "app" {
                result.append(child)
            } else if (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                result += appBundles(in: child, depth: depth - 1)
            }
        }
        return result
    }
}
