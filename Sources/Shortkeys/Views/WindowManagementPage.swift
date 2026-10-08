import KeyboardShortcuts
import Observation
import SwiftUI

/// Search text and filter for the Window Management page.
@MainActor
@Observable
final class WindowCommandsModel {
    static let shared = WindowCommandsModel()

    var search = ""
    var filter = ShortcutFilter.all
    /// Bumped when any shortcut changes, so the filtered list updates.
    private var shortcutRevision = 0

    private init() {
        NotificationCenter.default.observe(.shortcutDidChange) {
            WindowCommandsModel.shared.shortcutRevision += 1
        }
    }

    func commands(in section: WindowCommand.Section) -> [WindowCommand] {
        _ = shortcutRevision
        let query = search.trimmingCharacters(in: .whitespaces)
        return section.commands.filter { command in
            (query.isEmpty || command.title.localizedCaseInsensitiveContains(query))
                && (filter == .all || KeyboardShortcuts.getShortcut(for: command.shortcutName) != nil)
        }
    }

    var visibleCount: Int {
        WindowCommand.Section.allCases.reduce(0) { $0 + commands(in: $1).count }
    }
}

struct WindowManagementPage: View {
    @Bindable private var model = WindowCommandsModel.shared

    var body: some View {
        VStack(spacing: 0) {
            FilterHeader(
                search: $model.search,
                searchPrompt: "Search commands",
                filter: $model.filter,
                allTitle: "All commands",
                count: model.visibleCount,
                noun: ("command", "commands")
            )

            if model.visibleCount == 0 {
                if model.search.isEmpty {
                    ContentUnavailableView(
                        "No Window Hotkeys",
                        systemImage: "keyboard",
                        description: Text("Record a hotkey for a command under “All commands”.")
                    )
                } else {
                    ContentUnavailableView.search(text: model.search)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        ForEach(WindowCommand.Section.allCases) { section in
                            let commands = model.commands(in: section)
                            if !commands.isEmpty {
                                GroupedRows(title: section.rawValue, items: commands) { command in
                                    HStack(spacing: 10) {
                                        PositionIcon(command: command)
                                        Text(command.title)
                                        Spacer(minLength: 16)
                                        KeyboardShortcuts.Recorder(for: command.shortcutName)
                                    }
                                }
                            }
                        }
                    }
                    .padding(20)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("Window Management")
    }
}
