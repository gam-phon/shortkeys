import AppKit
import SwiftUI

enum ShortcutFilter: CaseIterable, Identifiable {
    case all, withShortcuts
    var id: Self { self }
}

/// Search field, "All … / With shortcuts only" filter and a result count,
/// shown at the top of the Apps and Window Management pages.
///
/// These live in the page, not the toolbar: toolbar controls make the title
/// bar taller, so pages with and without them (General, About) had different
/// title bars, and the window buttons moved when switching pages.
struct FilterHeader: View {
    @Binding var search: String
    let searchPrompt: String
    @Binding var filter: ShortcutFilter
    let allTitle: String
    let count: Int
    let noun: (singular: String, plural: String)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SearchField(text: $search, prompt: searchPrompt)
            HStack {
                Picker("Show", selection: $filter) {
                    Text(allTitle).tag(ShortcutFilter.all)
                    Text("With shortcuts only").tag(ShortcutFilter.withShortcuts)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Spacer()
                Text("\(count) \(count == 1 ? noun.singular : noun.plural)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }
}

/// The native macOS search field (clear button, Esc to clear), bound to a string.
private struct SearchField: NSViewRepresentable {
    @Binding var text: String
    let prompt: String

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = prompt
        field.sendsSearchStringImmediately = true
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.text = $text
        if field.stringValue != text {
            field.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            text.wrappedValue = field.stringValue
        }
    }
}
