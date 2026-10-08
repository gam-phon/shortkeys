Vendored KeyboardShortcuts 2.4.0 (https://github.com/sindresorhus/KeyboardShortcuts), MIT.

Patched so it builds against the macOS 27 SDK with only the Command Line Tools
(the SwiftUIMacros / PreviewsMacros compiler plugins ship only with Xcode):
- Recorder.swift: removed the three `#Preview` blocks.
- ViewModifiers.swift: replaced two `@State` properties with an `@StateObject`.
- Package.swift: removed the test target.
- KeyboardShortcuts.swift: `register(_:)` does nothing while `isEnabled` is false, so
  newly recorded shortcuts aren't grabbed by Carbon (Shortkeys uses a CGEvent tap).
- Localization/en.lproj: "Record Shortcut" placeholder reads "Record Hotkey".
- RecorderCocoa.swift: mouse-ups inside the recorder are passed through instead of swallowed.
  Swallowing them left the field's mouse-tracking loop running after a click, so the
  recorder never received key presses (clicking the box and pressing a hotkey did nothing).
- KeyboardShortcuts.swift: `isEnabled` is `nonisolated(unsafe)` (it's main-thread-only state),
  so the Swift 6 app can use it.
- RecorderCocoa.swift: the "Press Shortcut" placeholder and cancel button are set before
  editing starts. In apps built for macOS 26+, changing the placeholder during editing
  restarts editing, which ended recording the moment it began.
- Utilities.swift: `LocalEventMonitor` holds its monitor token strongly (it was weak).
- RecorderCocoa.swift: `controlTextDidEndEditing` only stops recording if editing has really
  ended (checked on the next run-loop turn). In apps built for macOS 26+, a click ends and
  immediately restarts editing.
