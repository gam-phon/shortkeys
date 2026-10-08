import CoreGraphics
import KeyboardShortcuts

/// Every window command, in the order shown in Settings (grouped by `section`).
enum WindowCommand: String, CaseIterable, Identifiable {
    // Halves
    case leftHalf, rightHalf, topHalf, bottomHalf, centerHalf
    // Quarters
    case topLeft, topRight, bottomLeft, bottomRight
    // Thirds
    case leftThird, centerThird, rightThird, leftTwoThirds, centerTwoThirds, rightTwoThirds
    case topThird, bottomThird, topTwoThirds, bottomTwoThirds, topCenterTwoThirds, bottomCenterTwoThirds
    // Fourths
    case firstFourth, secondFourth, thirdFourth, lastFourth
    case leftThreeFourths, centerThreeFourths, rightThreeFourths
    case topFourth, bottomFourth, topThreeFourths, bottomThreeFourths
    // Sixths
    case topLeftSixth, topCenterSixth, topRightSixth, bottomLeftSixth, bottomCenterSixth, bottomRightSixth
    // Size
    case maximize, almostMaximize, maximizeWidth, maximizeHeight, reasonableSize
    case makeLarger, makeSmaller, toggleFullscreen, restore
    // Move
    case center, moveUp, moveDown, moveLeft, moveRight
    // Displays
    case nextDisplay, previousDisplay

    enum Section: String, CaseIterable, Identifiable {
        case halves = "Halves"
        case quarters = "Quarters"
        case thirds = "Thirds"
        case fourths = "Fourths"
        case sixths = "Sixths"
        case size = "Size"
        case move = "Move"
        case displays = "Displays"

        var id: Self { self }
        var commands: [WindowCommand] { WindowCommand.allCases.filter { $0.section == self } }
    }

    var id: Self { self }

    var title: String {
        switch self {
        case .leftHalf: "Left Half"
        case .rightHalf: "Right Half"
        case .topHalf: "Top Half"
        case .bottomHalf: "Bottom Half"
        case .centerHalf: "Center Half"
        case .topLeft: "Top Left Quarter"
        case .topRight: "Top Right Quarter"
        case .bottomLeft: "Bottom Left Quarter"
        case .bottomRight: "Bottom Right Quarter"
        case .leftThird: "Left Third"
        case .centerThird: "Center Third"
        case .rightThird: "Right Third"
        case .leftTwoThirds: "Left Two Thirds"
        case .centerTwoThirds: "Center Two Thirds"
        case .rightTwoThirds: "Right Two Thirds"
        case .topThird: "Top Third"
        case .bottomThird: "Bottom Third"
        case .topTwoThirds: "Top Two Thirds"
        case .bottomTwoThirds: "Bottom Two Thirds"
        case .topCenterTwoThirds: "Top Center Two Thirds"
        case .bottomCenterTwoThirds: "Bottom Center Two Thirds"
        case .firstFourth: "First Fourth"
        case .secondFourth: "Second Fourth"
        case .thirdFourth: "Third Fourth"
        case .lastFourth: "Last Fourth"
        case .leftThreeFourths: "Left Three Fourths"
        case .centerThreeFourths: "Center Three Fourths"
        case .rightThreeFourths: "Right Three Fourths"
        case .topFourth: "Top Fourth"
        case .bottomFourth: "Bottom Fourth"
        case .topThreeFourths: "Top Three Fourths"
        case .bottomThreeFourths: "Bottom Three Fourths"
        case .topLeftSixth: "Top Left Sixth"
        case .topCenterSixth: "Top Center Sixth"
        case .topRightSixth: "Top Right Sixth"
        case .bottomLeftSixth: "Bottom Left Sixth"
        case .bottomCenterSixth: "Bottom Center Sixth"
        case .bottomRightSixth: "Bottom Right Sixth"
        case .maximize: "Maximize"
        case .almostMaximize: "Almost Maximize"
        case .maximizeWidth: "Maximize Width"
        case .maximizeHeight: "Maximize Height"
        case .reasonableSize: "Reasonable Size"
        case .makeLarger: "Make Larger"
        case .makeSmaller: "Make Smaller"
        case .toggleFullscreen: "Toggle Fullscreen"
        case .restore: "Restore Previous Size"
        case .center: "Center"
        case .moveUp: "Move Up"
        case .moveDown: "Move Down"
        case .moveLeft: "Move Left"
        case .moveRight: "Move Right"
        case .nextDisplay: "Next Display"
        case .previousDisplay: "Previous Display"
        }
    }

    var section: Section {
        switch self {
        case .leftHalf, .rightHalf, .topHalf, .bottomHalf, .centerHalf:
            .halves
        case .topLeft, .topRight, .bottomLeft, .bottomRight:
            .quarters
        case .leftThird, .centerThird, .rightThird, .leftTwoThirds, .centerTwoThirds, .rightTwoThirds,
             .topThird, .bottomThird, .topTwoThirds, .bottomTwoThirds, .topCenterTwoThirds, .bottomCenterTwoThirds:
            .thirds
        case .firstFourth, .secondFourth, .thirdFourth, .lastFourth,
             .leftThreeFourths, .centerThreeFourths, .rightThreeFourths,
             .topFourth, .bottomFourth, .topThreeFourths, .bottomThreeFourths:
            .fourths
        case .topLeftSixth, .topCenterSixth, .topRightSixth, .bottomLeftSixth, .bottomCenterSixth, .bottomRightSixth:
            .sixths
        case .maximize, .almostMaximize, .maximizeWidth, .maximizeHeight, .reasonableSize,
             .makeLarger, .makeSmaller, .toggleFullscreen, .restore:
            .size
        case .center, .moveUp, .moveDown, .moveLeft, .moveRight:
            .move
        case .nextDisplay, .previousDisplay:
            .displays
        }
    }

    /// Target area as a fraction of the visible screen, with a top-left origin
    /// (y grows downwards), which is also how the settings icons draw it.
    /// Nil for commands that depend on the window's current frame.
    var unitRect: CGRect? {
        let third = 1.0 / 3.0, sixth = 1.0 / 6.0
        return switch self {
        case .leftHalf: CGRect(x: 0, y: 0, width: 0.5, height: 1)
        case .rightHalf: CGRect(x: 0.5, y: 0, width: 0.5, height: 1)
        case .topHalf: CGRect(x: 0, y: 0, width: 1, height: 0.5)
        case .bottomHalf: CGRect(x: 0, y: 0.5, width: 1, height: 0.5)
        case .centerHalf: CGRect(x: 0.25, y: 0, width: 0.5, height: 1)

        case .topLeft: CGRect(x: 0, y: 0, width: 0.5, height: 0.5)
        case .topRight: CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5)
        case .bottomLeft: CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5)
        case .bottomRight: CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)

        case .leftThird: CGRect(x: 0, y: 0, width: third, height: 1)
        case .centerThird: CGRect(x: third, y: 0, width: third, height: 1)
        case .rightThird: CGRect(x: 2 * third, y: 0, width: third, height: 1)
        case .leftTwoThirds: CGRect(x: 0, y: 0, width: 2 * third, height: 1)
        case .centerTwoThirds: CGRect(x: sixth, y: 0, width: 2 * third, height: 1)
        case .rightTwoThirds: CGRect(x: third, y: 0, width: 2 * third, height: 1)
        case .topThird: CGRect(x: 0, y: 0, width: 1, height: third)
        case .bottomThird: CGRect(x: 0, y: 2 * third, width: 1, height: third)
        case .topTwoThirds: CGRect(x: 0, y: 0, width: 1, height: 2 * third)
        case .bottomTwoThirds: CGRect(x: 0, y: third, width: 1, height: 2 * third)
        case .topCenterTwoThirds: CGRect(x: sixth, y: 0, width: 2 * third, height: 2 * third)
        case .bottomCenterTwoThirds: CGRect(x: sixth, y: third, width: 2 * third, height: 2 * third)

        case .firstFourth: CGRect(x: 0, y: 0, width: 0.25, height: 1)
        case .secondFourth: CGRect(x: 0.25, y: 0, width: 0.25, height: 1)
        case .thirdFourth: CGRect(x: 0.5, y: 0, width: 0.25, height: 1)
        case .lastFourth: CGRect(x: 0.75, y: 0, width: 0.25, height: 1)
        case .leftThreeFourths: CGRect(x: 0, y: 0, width: 0.75, height: 1)
        case .centerThreeFourths: CGRect(x: 0.125, y: 0, width: 0.75, height: 1)
        case .rightThreeFourths: CGRect(x: 0.25, y: 0, width: 0.75, height: 1)
        case .topFourth: CGRect(x: 0, y: 0, width: 1, height: 0.25)
        case .bottomFourth: CGRect(x: 0, y: 0.75, width: 1, height: 0.25)
        case .topThreeFourths: CGRect(x: 0, y: 0, width: 1, height: 0.75)
        case .bottomThreeFourths: CGRect(x: 0, y: 0.25, width: 1, height: 0.75)

        case .topLeftSixth: CGRect(x: 0, y: 0, width: third, height: 0.5)
        case .topCenterSixth: CGRect(x: third, y: 0, width: third, height: 0.5)
        case .topRightSixth: CGRect(x: 2 * third, y: 0, width: third, height: 0.5)
        case .bottomLeftSixth: CGRect(x: 0, y: 0.5, width: third, height: 0.5)
        case .bottomCenterSixth: CGRect(x: third, y: 0.5, width: third, height: 0.5)
        case .bottomRightSixth: CGRect(x: 2 * third, y: 0.5, width: third, height: 0.5)

        case .maximize: CGRect(x: 0, y: 0, width: 1, height: 1)
        case .almostMaximize: CGRect(x: 0.05, y: 0.05, width: 0.9, height: 0.9)
        case .reasonableSize: CGRect(x: 0.2, y: 0.15, width: 0.6, height: 0.7)

        case .maximizeWidth, .maximizeHeight, .makeLarger, .makeSmaller, .toggleFullscreen, .restore,
             .center, .moveUp, .moveDown, .moveLeft, .moveRight, .nextDisplay, .previousDisplay:
            nil
        }
    }

    var shortcutName: KeyboardShortcuts.Name {
        let defaultShortcut: KeyboardShortcuts.Shortcut? = switch self {
        // Defaults on ⌃⌥ (Vim-style for the halves).
        case .leftHalf: .init(.h, modifiers: [.control, .option])
        case .rightHalf: .init(.l, modifiers: [.control, .option])
        case .topHalf: .init(.k, modifiers: [.control, .option])
        case .bottomHalf: .init(.j, modifiers: [.control, .option])
        case .maximize: .init(.m, modifiers: [.control, .option])
        case .topCenterTwoThirds: .init(.o, modifiers: [.control, .option])
        default: nil
        }
        return KeyboardShortcuts.Name("window:\(rawValue)", default: defaultShortcut)
    }
}
