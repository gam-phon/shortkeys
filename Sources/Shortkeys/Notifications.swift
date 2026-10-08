import Foundation
import KeyboardShortcuts

extension NotificationCenter {
    /// Observes `name` for the app's lifetime and runs `handler` on the main actor.
    ///
    /// The typed `addObserver(of:for:)` messages (macOS 26+) were tried and did
    /// not deliver AppKit's or KeyboardShortcuts' notifications, so observation
    /// is by name.
    func observe(_ name: Notification.Name, handler: @escaping @MainActor () -> Void) {
        observe(name, value: { _ in () }) { _ in handler() }
    }

    /// Like `observe(_:handler:)`, passing a value read from the notification
    /// (it's read before hopping to the main actor, as `Notification` isn't `Sendable`).
    func observe<Value: Sendable>(
        _ name: Notification.Name,
        value: @escaping @Sendable (Notification) -> Value,
        handler: @escaping @MainActor (Value) -> Void
    ) {
        addObserver(forName: name, object: nil, queue: .main) { notification in
            let value = value(notification)
            // `queue: .main` runs this block on the main thread.
            MainActor.assumeIsolated { handler(value) }
        }
    }
}

extension Notification.Name {
    /// Posted by KeyboardShortcuts when a shortcut is recorded, changed or cleared;
    /// `userInfo["name"]` is the `KeyboardShortcuts.Name`.
    static let shortcutDidChange = Self("KeyboardShortcuts_shortcutByNameDidChange")
    /// Posted by KeyboardShortcuts when a recorder starts or stops recording;
    /// `userInfo["isActive"]` is a `Bool`.
    static let recorderActiveDidChange = Self("KeyboardShortcuts_recorderActiveStatusDidChange")
}

extension Notification {
    /// The shortcut a `.shortcutDidChange` notification is about.
    var shortcutName: KeyboardShortcuts.Name? { userInfo?["name"] as? KeyboardShortcuts.Name }
    /// Whether a recorder is active, for `.recorderActiveDidChange`.
    var isRecorderActive: Bool { userInfo?["isActive"] as? Bool ?? false }
}
