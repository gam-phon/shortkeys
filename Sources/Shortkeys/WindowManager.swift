import AppKit
import ApplicationServices

/// Moves and resizes the focused window through the Accessibility API.
///
/// Coordinates: AX uses a global space with the origin at the top-left of the
/// primary display and y growing downwards. AppKit (`NSScreen.frame`,
/// `visibleFrame`) uses the bottom-left of the primary display with y growing
/// upwards. All layout math happens in AppKit space; we convert at the edges.
@MainActor
final class WindowManager {
    static let shared = WindowManager()

    /// The frame before Shortkeys first moved a window, for "Restore".
    private struct History {
        let window: AXUIElement
        var original: CGRect
        var lastSet: CGRect
    }
    private var history: [History] = []

    func perform(_ command: WindowCommand) {
        guard let window = focusedWindow() else {
            NSSound.beep()
            return
        }
        let isFullScreen = AX.bool(window, "AXFullScreen") == true
        if command == .toggleFullscreen {
            AXUIElementSetAttributeValue(window, "AXFullScreen" as CFString, (!isFullScreen) as CFBoolean)
            return
        }
        if isFullScreen { return }
        guard let current = frame(of: window) else { return }
        let screens = NSScreen.screens
        let screenIndex = WindowGeometry.bestScreen(for: current, among: screens.map(\.frame))
            ?? NSScreen.main.flatMap { screens.firstIndex(of: $0) } ?? 0
        guard screens.indices.contains(screenIndex) else { return }
        let visible = screens[screenIndex].visibleFrame

        let target: CGRect
        switch command {
        case .restore:
            guard let index = historyIndex(for: window) else { return }
            setFrame(history[index].original, of: window)
            history.remove(at: index)
            return

        case .center:
            target = WindowGeometry.centered(current, in: visible)

        case .maximizeWidth:
            target = WindowGeometry.maximizedWidth(current, in: visible)
        case .maximizeHeight:
            target = WindowGeometry.maximizedHeight(current, in: visible)
        case .makeLarger:
            target = WindowGeometry.resized(current, by: 0.05, in: visible)
        case .makeSmaller:
            target = WindowGeometry.resized(current, by: -0.05, in: visible)
        case .moveUp:
            target = WindowGeometry.moved(current, to: .top, in: visible)
        case .moveDown:
            target = WindowGeometry.moved(current, to: .bottom, in: visible)
        case .moveLeft:
            target = WindowGeometry.moved(current, to: .left, in: visible)
        case .moveRight:
            target = WindowGeometry.moved(current, to: .right, in: visible)

        case .nextDisplay, .previousDisplay:
            guard let next = WindowGeometry.adjacentScreen(
                to: screenIndex, among: screens.map(\.frame), forward: command == .nextDisplay)
            else { return }
            target = WindowGeometry.map(current, from: visible, to: screens[next].visibleFrame)

        default:
            guard let unit = command.unitRect else { return }
            target = WindowGeometry.rect(for: unit, in: visible)
        }

        remember(window, current: current)
        setFrame(target, of: window)
        if let index = historyIndex(for: window), let actual = frame(of: window) {
            history[index].lastSet = actual
        }
    }

    // MARK: - Restore history

    private func historyIndex(for window: AXUIElement) -> Int? {
        history.firstIndex { CFEqual($0.window, window) }
    }

    /// Saves the frame to restore to, unless the window is still where we last
    /// put it (chained commands keep the original pre-Shortkeys frame).
    private func remember(_ window: AXUIElement, current: CGRect) {
        if let index = historyIndex(for: window) {
            if !approximatelyEqual(history[index].lastSet, current) {
                history[index].original = current
            }
            return
        }
        history.append(History(window: window, original: current, lastSet: current))
        if history.count > 50 { history.removeFirst() }
    }

    private func approximatelyEqual(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 2 && abs(a.minY - b.minY) < 2
            && abs(a.width - b.width) < 2 && abs(a.height - b.height) < 2
    }

    // MARK: - Accessibility

    private func focusedWindow() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        guard let value = AX.value(axApp, kAXFocusedWindowAttribute) else { return nil }
        return (value as! AXUIElement)
    }

    /// The window's frame in AppKit coordinates.
    private func frame(of window: AXUIElement) -> CGRect? {
        guard
            let positionValue = AX.value(window, kAXPositionAttribute),
            let sizeValue = AX.value(window, kAXSizeAttribute)
        else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        return flip(CGRect(origin: position, size: size))
    }

    /// Sets the window's frame, given in AppKit coordinates.
    private func setFrame(_ frame: CGRect, of window: AXUIElement) {
        let axFrame = flip(frame)
        var position = axFrame.origin
        var size = axFrame.size
        guard
            let positionValue = AXValueCreate(.cgPoint, &position),
            let sizeValue = AXValueCreate(.cgSize, &size)
        else { return }

        // Apps with "enhanced user interface" on (set by some assistive tools)
        // animate every AX change, which makes moves slow and imprecise.
        let app = appElement(of: window)
        let enhanced = app.flatMap { AX.bool($0, "AXEnhancedUserInterface") } ?? false
        if enhanced, let app {
            AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanFalse)
        }

        // Size, then position, then size again: moving to a smaller display can
        // clamp the size, and growing in place can be blocked by the screen edge.
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)

        if enhanced, let app {
            AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        }
    }

    private func appElement(of window: AXUIElement) -> AXUIElement? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(window, &pid) == .success else { return nil }
        return AXUIElementCreateApplication(pid)
    }

    private func flip(_ rect: CGRect) -> CGRect {
        // NSScreen.screens[0] is the primary display (the one with the menu bar).
        WindowGeometry.flip(rect, primaryHeight: NSScreen.screens.first?.frame.maxY ?? 0)
    }
}
