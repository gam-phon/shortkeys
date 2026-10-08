# Shortkeys: notes for Claude Code

A menu bar app for macOS 27+ with app-launch hotkeys and window-management
hotkeys. It's built with Swift 6 + SwiftUI via SwiftPM. User docs are in
README.md.

## Ground rules from the owner

- **macOS 27+ only.** Don't add fallbacks or availability checks for older
  macOS.
- **No deprecated APIs.** Use the current recommended macOS 27 APIs and modern
  SwiftUI. A clean build must have zero warnings.
- **Verify before saying it works.** Run the tests below. UI changes need a
  snapshot check.

## Building

- `./build.sh` builds `build/Shortkeys.app` and signs it with the
  self-signed "Shortkeys Dev" identity. `./install.sh` copies it to
  /Applications. `scripts/package.sh` makes the .pkg and .zip.
- The local Mac has **only the Command Line Tools**, no Xcode. In the macOS 27
  SDK, SwiftUI's `@State` and `#Preview` are macros whose plugins ship only
  with Xcode, so:
  - never use `@State` or `#Preview`;
  - keep view state in `@Observable` singletons with `@Bindable`, or use
    `@AppStorage`.
- Inside Claude Code's sandbox, SwiftPM fails: its nested sandbox and git
  writes are blocked. Run the build outside the sandbox.
- `build.sh` unregisters `build/Shortkeys.app` from Launch Services, and
  `install.sh` moves the app rather than copying it. This keeps a stray build
  copy from being opened instead of /Applications. Its Accessibility grant
  differs from the release build's, because it has a different signature.
  After testing, delete `build/` if an installed copy exists.
- **Quit Shortkeys before rebuilding.** Replacing the binary of the running
  app gets it killed.
- Signing fails with `errSecInternalComponent` if the key's partition list
  isn't set. The fix is in README → Troubleshooting.
- The shell's `log` is overridden, so use `/usr/bin/log`. Debug-level log
  messages aren't persisted, so use `.info`.
- The global gitignore has `*.sw*`, which matches `.swift`. The repo
  `.gitignore` re-includes Swift files with `!*.swift`.

## Testing

```sh
scripts/test-geometry.sh                                   # pure layout maths
open build/Shortkeys.app --args --snapshot /tmp/sk-snaps   # PNG of every page + selftest.txt
open build/Shortkeys.app --args --e2e-test /tmp/sk-e2e     # real clicks/keys: record ⌥N via the UI
```

- `--snapshot` captures the window offscreen. It can't show live effects such
  as translucency or the selected sidebar row's highlight.
- `--e2e-test` posts real input events (it needs Accessibility) and restores
  the shortcuts it changes.
- Always rerun `--e2e-test` after touching the recorder, the settings layout,
  activation, or the deployment target.

## Architecture

- **Hotkeys.**
  - `HotkeyCenter` matches key-downs in a CGEvent tap, and asks before reusing
    a hotkey that's already taken.
  - KeyboardShortcuts only stores shortcuts and provides the recorder. Its
    Carbon backend is disabled (`isEnabled = false`), because Carbon hotkeys
    didn't deliver here.
- **App launching.** `AppHotkeys` keeps a registry of bundle IDs.
  `AppLauncher` does launch, activate, and window cycling.
- **Windows.**
  - `WindowManager` gets and sets frames through AX.
  - `WindowGeometry` holds the pure maths (AX↔AppKit flip, layouts, display
    mapping), and `scripts/test-geometry.swift` tests it.
  - `WindowCommand` defines the commands, their unit rects and the default
    hotkeys.
- **Settings window.**
  - It's a `Window` scene with `NavigationSplitView`. The sidebar is always
    visible and there's no toolbar toggle: collapsing it made the page jump.
  - Search and filter sit in the page (`FilterHeader`), not the toolbar:
    toolbar controls change the title-bar height between pages.
  - Rows use `GroupedRows`/`SettingsGroup` (a LazyVStack), never `List` or
    `Form`: table views steal focus from recorders.
- **Settings layout pitfalls.** All three were found the hard way:
  - Never use `.fixedSize(horizontal: false, vertical: true)` on text in the
    settings pages. With `.windowResizability(.contentMinSize)`, SwiftUI then
    measures the text one word per line, and the window contents grow
    thousands of points tall.
  - `.navigationSplitViewColumnWidth` must come after
    `.toolbar(removing: .sidebarToggle)`, or it's ignored and the sidebar
    falls back to 140 points.
  - A SwiftUI window's `contentMinSize` is zero; use
    `SettingsView.minimumSize`. The saved split position is cleared at launch.
- **Opening Settings.** `SettingsWindow.open()` activates through
  LaunchServices, opening its own bundle, because `NSApp.activate()` is
  declined for a menu bar app. The reopen event then calls `show()`.
  `openWindow` is captured from the app's `.commands`, which also works when
  the menu bar icon is hidden.
- **Staying alive.**
  - `applicationShouldTerminateAfterLastWindowClosed` returns false; without
    it, closing the menu or Settings quit the app.
  - Automatic termination is disabled.
- **Notifications.** Observe them by name with `NotificationCenter.observe`.
  The macOS 26+ typed messages (`addObserver(of:for:)`) don't deliver here.

## Releases and updates

- **Signing.** Releases are signed by CI with the "Shortkeys Dev" certificate,
  which is stored in repo secrets. The same identity is in the owner's login
  keychain. Its leaf hash is b5641894…; changing it breaks updates and the
  Accessibility grants.
- **The updater** (`Updater.swift`) checks GitHub's latest release, verifies
  its SHA-256 and that the update satisfies the running app's designated
  requirement, then swaps the app via a helper script and relaunches.
  `--update-test` installs the latest release regardless of version.
- **Ownership.** The .pkg installs as root, so postinstall `chown`s the app
  to the user. Update and uninstall fall back to `AdminPrompt` (the standard
  password dialog) for a root-owned copy.
- **Test hygiene.** `--update-test` relaunches the updated copy as a normal
  app. Afterwards, wait for the relaunch, kill it, and check
  `ps -axo command | grep Shortkeys.app` for strays. A stray once kept
  rewriting settings and showed permission prompts to the user.
- **Install script.** `scripts/install-latest.sh` (curl | bash) installs or
  updates on any Mac. The .pkg's preinstall and postinstall scripts quit and
  reopen the app.

## Vendored KeyboardShortcuts

`Vendor/KeyboardShortcuts` is version 2.4.0 with patches, listed in its
`PATCHES.md`. Two of them matter most for apps built for macOS 26+, where a
click restarts text editing:

- The recorder sets its placeholder before editing starts.
- It only ends recording when editing has really ended.
