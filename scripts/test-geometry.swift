// Tests WindowGeometry with made-up multi-display layouts. Run: scripts/test-geometry.sh
import CoreGraphics

var failures = 0
func check(_ label: String, _ actual: CGRect, _ expected: CGRect) {
    if actual == expected {
        print("ok   \(label)")
    } else {
        failures += 1
        print("FAIL \(label): got \(actual), expected \(expected)")
    }
}
func check<T: Equatable>(_ label: String, _ actual: T, _ expected: T) {
    if actual == expected { print("ok   \(label)") } else { failures += 1; print("FAIL \(label): got \(actual), expected \(expected)") }
}
let R = CGRect.init(x:y:width:height:) as (CGFloat, CGFloat, CGFloat, CGFloat) -> CGRect

// Unit rects as in WindowCommand (top-left origin).
let leftHalf = R(0, 0, 0.5, 1), rightHalf = R(0.5, 0, 0.5, 1)
let topHalf = R(0, 0, 1, 0.5), bottomHalf = R(0, 0.5, 1, 0.5)
let topRight = R(0.5, 0, 0.5, 0.5), bottomLeft = R(0, 0.5, 0.5, 0.5)
let third = 1.0 / 3.0
let rightThird = R(2 * third, 0, third, 1), centerThird = R(third, 0, third, 1)
let leftTwoThirds = R(0, 0, 2 * third, 1)
let almostMax = R(0.05, 0.05, 0.9, 0.9)

// Primary: MacBook 1728x1117, menu bar 37pt on top, Dock 60pt at the bottom.
let primary = R(0, 0, 1728, 1117)
let primaryVisible = R(0, 60, 1728, 1020)

print("— Single display layouts")
check("left half", WindowGeometry.rect(for: leftHalf, in: primaryVisible), R(0, 60, 864, 1020))
check("right half", WindowGeometry.rect(for: rightHalf, in: primaryVisible), R(864, 60, 864, 1020))
check("top half sits under the menu bar", WindowGeometry.rect(for: topHalf, in: primaryVisible), R(0, 570, 1728, 510))
check("bottom half sits above the Dock", WindowGeometry.rect(for: bottomHalf, in: primaryVisible), R(0, 60, 1728, 510))
check("top right quarter", WindowGeometry.rect(for: topRight, in: primaryVisible), R(864, 570, 864, 510))
check("bottom left quarter", WindowGeometry.rect(for: bottomLeft, in: primaryVisible), R(0, 60, 864, 510))
check("right third", WindowGeometry.rect(for: rightThird, in: primaryVisible), R(1152, 60, 576, 1020))
check("center third", WindowGeometry.rect(for: centerThird, in: primaryVisible), R(576, 60, 576, 1020))
check("left two thirds", WindowGeometry.rect(for: leftTwoThirds, in: primaryVisible), R(0, 60, 1152, 1020))
check("almost maximize", WindowGeometry.rect(for: almostMax, in: primaryVisible), R(86, 111, 1556, 918))
check("center keeps size", WindowGeometry.centered(R(10, 70, 800, 600), in: primaryVisible), R(464, 270, 800, 600))
check("center shrinks oversized window", WindowGeometry.centered(R(0, 0, 3000, 2000), in: primaryVisible), primaryVisible)

print("— AX ⇄ AppKit conversion")
// A window at the top-left of the primary's visible area: AX y = 37 (below the menu bar).
check("AX → AppKit on primary", WindowGeometry.flip(R(0, 37, 800, 600), primaryHeight: 1117), R(0, 480, 800, 600))
check("AppKit → AX on primary", WindowGeometry.flip(R(0, 480, 800, 600), primaryHeight: 1117), R(0, 37, 800, 600))

// External 2560x1440 to the right, its bottom 300pt below the primary's bottom.
let external = R(1728, -300, 2560, 1440)
let externalVisible = R(1728, -300, 2560, 1415) // 25pt menu bar, no Dock
// Its top edge is at AppKit y = 1140, which is AX y = 1117 - 1140 = -23.
check("AX → AppKit on taller right display", WindowGeometry.flip(R(1728, -23, 1000, 700), primaryHeight: 1117), R(1728, 440, 1000, 700))
let roundTrip = R(2000, -250, 640, 480)
check("flip is its own inverse", WindowGeometry.flip(WindowGeometry.flip(roundTrip, primaryHeight: 1117), primaryHeight: 1117), roundTrip)
check("left half on external", WindowGeometry.rect(for: leftHalf, in: externalVisible), R(1728, -300, 1280, 1415))
check("top half on external", WindowGeometry.rect(for: topHalf, in: externalVisible), R(1728, 408, 2560, 707))
// 1415pt is odd: the halves must still meet exactly, with no gap or overlap.
let extTop = WindowGeometry.rect(for: topHalf, in: externalVisible)
let extBottom = WindowGeometry.rect(for: bottomHalf, in: externalVisible)
check("odd height: halves meet exactly", extBottom.maxY, extTop.minY)
check("odd height: halves cover the screen", extBottom.union(extTop), externalVisible)
let thirds = [R(0, 0, third, 1), centerThird, rightThird].map { WindowGeometry.rect(for: $0, in: externalVisible) }
check("thirds tile exactly", thirds[0].maxX == thirds[1].minX && thirds[1].maxX == thirds[2].minX && thirds[2].maxX == externalVisible.maxX, true)

print("— Which display a window is on")
let screens = [primary, external]
check("window on primary", WindowGeometry.bestScreen(for: R(100, 100, 500, 500), among: screens), 0)
check("window on external", WindowGeometry.bestScreen(for: R(2000, 0, 500, 500), among: screens), 1)
check("straddling, mostly external", WindowGeometry.bestScreen(for: R(1600, 100, 800, 500), among: screens), 1)
check("off-screen window", WindowGeometry.bestScreen(for: R(9000, 9000, 10, 10), among: screens), nil)

print("— Next / previous display")
check("next from primary", WindowGeometry.adjacentScreen(to: 0, among: screens, forward: true), 1)
check("next wraps around", WindowGeometry.adjacentScreen(to: 1, among: screens, forward: true), 0)
check("previous from primary wraps", WindowGeometry.adjacentScreen(to: 0, among: screens, forward: false), 1)
check("single display has no next", WindowGeometry.adjacentScreen(to: 0, among: [primary], forward: true), nil)
// Three displays: one left of the primary (negative x), primary, one right; given out of order.
let left = R(-1920, 0, 1920, 1080)
let three = [primary, external, left]
check("left → primary", WindowGeometry.adjacentScreen(to: 2, among: three, forward: true), 0)
check("primary → right", WindowGeometry.adjacentScreen(to: 0, among: three, forward: true), 1)
check("left ← wraps to right", WindowGeometry.adjacentScreen(to: 2, among: three, forward: false), 1)
// Stacked: a display above the primary at the same x goes after it (top first).
let above = R(0, 1117, 1920, 1080)
check("above comes before primary at same x", WindowGeometry.adjacentScreen(to: 1, among: [primary, above], forward: true), 0)

print("— Moving between displays")
check("left half → left half of external",
      WindowGeometry.map(R(0, 60, 864, 1020), from: primaryVisible, to: externalVisible), R(1728, -300, 1280, 1415))
check("bottom-right quarter keeps its place",
      WindowGeometry.map(R(864, 60, 864, 510), from: primaryVisible, to: externalVisible), R(3008, -300, 1280, 708))
check("back to primary restores the layout",
      WindowGeometry.map(R(1728, -300, 1280, 1415), from: externalVisible, to: primaryVisible), R(0, 60, 864, 1020))
let leftVisible = R(-1920, 0, 1920, 1055)
let moved = WindowGeometry.map(R(200, 300, 800, 600), from: primaryVisible, to: leftVisible)
check("onto a display with negative x stays inside it", leftVisible.contains(moved), true)
let oversized = WindowGeometry.map(R(-50, 0, 2000, 1200), from: primaryVisible, to: leftVisible)
check("oversized window is clamped inside", leftVisible.contains(oversized), true)

print("— Size and move")
let window = R(300, 300, 800, 600)
check("maximize width keeps height and position", WindowGeometry.maximizedWidth(window, in: primaryVisible), R(0, 300, 1728, 600))
check("maximize height keeps width and position", WindowGeometry.maximizedHeight(window, in: primaryVisible), R(300, 60, 800, 1020))
let larger = WindowGeometry.resized(window, by: 0.05, in: primaryVisible)
check("make larger grows around the center", abs(larger.midX - window.midX) <= 1 && abs(larger.midY - window.midY) <= 1 && larger.width > window.width && larger.height > window.height, true)
let smaller = WindowGeometry.resized(window, by: -0.05, in: primaryVisible)
check("make smaller shrinks around the center", smaller.width < window.width && smaller.height < window.height, true)
check("make smaller stops at a minimum size", WindowGeometry.resized(R(300, 300, 410, 310), by: -0.5, in: primaryVisible).size, CGSize(width: 400, height: 300))
check("make larger never exceeds the screen", primaryVisible.contains(WindowGeometry.resized(R(0, 60, 1700, 1000), by: 0.5, in: primaryVisible)), true)
check("move up sits under the menu bar", WindowGeometry.moved(window, to: .top, in: primaryVisible), R(300, 480, 800, 600))
check("move down sits above the Dock", WindowGeometry.moved(window, to: .bottom, in: primaryVisible), R(300, 60, 800, 600))
check("move left", WindowGeometry.moved(window, to: .left, in: primaryVisible), R(0, 300, 800, 600))
check("move right", WindowGeometry.moved(window, to: .right, in: primaryVisible), R(928, 300, 800, 600))
check("top center two thirds", WindowGeometry.rect(for: R(1.0 / 6, 0, 2.0 / 3, 2.0 / 3), in: primaryVisible), R(288, 400, 1152, 680))

print(failures == 0 ? "\nAll geometry tests passed." : "\n\(failures) geometry test(s) FAILED.")
if failures > 0 { exit(1) }
