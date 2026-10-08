import SwiftUI

/// A titled, rounded group of rows in the System Settings style.
///
/// Settings pages use this instead of `List`/`Form`: those are backed by a
/// table view that takes keyboard focus back when a row is clicked, which
/// stops a `KeyboardShortcuts.Recorder` in that row from receiving the keys.
/// Rows are created lazily, so long app lists stay cheap.
struct GroupedRows<Item: Identifiable, Row: View>: View {
    var title: String?
    let items: [Item]
    @ViewBuilder let row: (Item) -> Row

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.headline)
                    .padding(.leading, 4)
            }
            LazyVStack(spacing: 0) {
                ForEach(items) { item in
                    row(item)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                    if item.id != items.last?.id {
                        Divider().padding(.leading, 12)
                    }
                }
            }
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(.separator.opacity(0.6))
            }
        }
    }
}

/// A titled, rounded group with arbitrary rows, for pages like General whose
/// rows aren't a list of items. Separate rows with `Divider()`.
struct SettingsGroup<Content: View>: View {
    var title: String?
    var footer: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.headline)
                    .padding(.leading, 4)
            }
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(.separator.opacity(0.6))
            }
            if let footer {
                Text(footer)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
