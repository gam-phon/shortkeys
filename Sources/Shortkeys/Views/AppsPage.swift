import KeyboardShortcuts
import SwiftUI

struct AppsPage: View {
    @Bindable private var catalog = AppCatalog.shared

    var body: some View {
        VStack(spacing: 0) {
            FilterHeader(
                search: $catalog.search,
                searchPrompt: "Search apps",
                filter: $catalog.filter,
                allTitle: "All apps",
                count: catalog.visible.count,
                noun: ("app", "apps")
            )

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Apps")
        .task { await catalog.loadIfNeeded() }
    }

    @ViewBuilder private var content: some View {
        let apps = catalog.visible
        if catalog.entries.isEmpty && catalog.isLoading {
            ProgressView("Loading apps…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if apps.isEmpty {
            if catalog.search.isEmpty {
                ContentUnavailableView(
                    "No App Hotkeys",
                    systemImage: "keyboard",
                    description: Text("Record a hotkey for an app under “All apps”.")
                )
            } else {
                ContentUnavailableView.search(text: catalog.search)
            }
        } else {
            ScrollView {
                GroupedRows(items: apps) { app in
                    AppRow(app: app)
                }
                .padding(20)
            }
        }
    }
}

private struct AppRow: View {
    let app: AppCatalog.Entry

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: AppCatalog.shared.icon(for: app))
                .resizable()
                .frame(width: 24, height: 24)
            Text(app.name)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 16)
            KeyboardShortcuts.Recorder(for: AppHotkeys.name(for: app.id))
        }
    }
}
