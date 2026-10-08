import CoreGraphics

/// Pure layout math, kept free of AppKit so it can be tested with made-up
/// screen layouts (`scripts/test-geometry.sh`). All rects are AppKit global
/// coordinates (origin bottom-left of the primary display) unless noted.
enum WindowGeometry {
    /// Converts between AX (top-left origin, y down) and AppKit (bottom-left
    /// origin, y up) global coordinates. Both are anchored to the primary
    /// display, whose height is `primaryHeight`. The flip is its own inverse.
    static func flip(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Converts a top-left-origin unit rect into a rect inside `visible`.
    static func rect(for unit: CGRect, in visible: CGRect) -> CGRect {
        CGRect(
            x: visible.minX + unit.minX * visible.width,
            y: visible.maxY - unit.maxY * visible.height,
            width: unit.width * visible.width,
            height: unit.height * visible.height
        ).snapped
    }

    /// `frame`'s size, centered in `visible` (shrunk to fit if needed).
    static func centered(_ frame: CGRect, in visible: CGRect) -> CGRect {
        let width = min(frame.width, visible.width)
        let height = min(frame.height, visible.height)
        return CGRect(x: visible.midX - width / 2, y: visible.midY - height / 2, width: width, height: height).snapped
    }

    /// Keeps the window's relative position and size when moving between displays.
    static func map(_ frame: CGRect, from source: CGRect, to destination: CGRect) -> CGRect {
        let scaleX = destination.width / source.width
        let scaleY = destination.height / source.height
        var result = CGRect(
            x: destination.minX + (frame.minX - source.minX) * scaleX,
            y: destination.minY + (frame.minY - source.minY) * scaleY,
            width: min(frame.width * scaleX, destination.width),
            height: min(frame.height * scaleY, destination.height)
        )
        // Clamp fully inside the destination's visible area.
        result.origin.x = min(max(result.minX, destination.minX), destination.maxX - result.width)
        result.origin.y = min(max(result.minY, destination.minY), destination.maxY - result.height)
        return result.snapped
    }

    /// Full width of `visible`, keeping the window's vertical position and height.
    static func maximizedWidth(_ frame: CGRect, in visible: CGRect) -> CGRect {
        clamped(CGRect(x: visible.minX, y: frame.minY, width: visible.width, height: frame.height), in: visible)
    }

    /// Full height of `visible`, keeping the window's horizontal position and width.
    static func maximizedHeight(_ frame: CGRect, in visible: CGRect) -> CGRect {
        clamped(CGRect(x: frame.minX, y: visible.minY, width: frame.width, height: visible.height), in: visible)
    }

    /// Grows (positive `step`) or shrinks the window around its center by
    /// `step` of the screen's size on each axis, staying inside `visible`.
    static func resized(_ frame: CGRect, by step: CGFloat, in visible: CGRect) -> CGRect {
        let minimum = CGSize(width: min(400, visible.width), height: min(300, visible.height))
        let width = min(max(frame.width + step * visible.width, minimum.width), visible.width)
        let height = min(max(frame.height + step * visible.height, minimum.height), visible.height)
        return clamped(
            CGRect(x: frame.midX - width / 2, y: frame.midY - height / 2, width: width, height: height),
            in: visible
        )
    }

    enum Edge { case top, bottom, left, right }

    /// Moves the window against one edge of `visible`, keeping its size.
    static func moved(_ frame: CGRect, to edge: Edge, in visible: CGRect) -> CGRect {
        var result = clamped(frame, in: visible)
        switch edge {
        case .top: result.origin.y = visible.maxY - result.height // AppKit: y grows upwards
        case .bottom: result.origin.y = visible.minY
        case .left: result.origin.x = visible.minX
        case .right: result.origin.x = visible.maxX - result.width
        }
        return result.snapped
    }

    /// `frame` shrunk to fit and moved fully inside `visible`.
    static func clamped(_ frame: CGRect, in visible: CGRect) -> CGRect {
        var result = frame
        result.size.width = min(result.width, visible.width)
        result.size.height = min(result.height, visible.height)
        result.origin.x = min(max(result.minX, visible.minX), visible.maxX - result.width)
        result.origin.y = min(max(result.minY, visible.minY), visible.maxY - result.height)
        return result.snapped
    }

    /// Index of the screen showing most of `frame`, or nil if it's on none.
    static func bestScreen(for frame: CGRect, among screens: [CGRect]) -> Int? {
        let areas = screens.map { area($0.intersection(frame)) }
        guard let best = areas.indices.max(by: { areas[$0] < areas[$1] }), areas[best] > 0 else { return nil }
        return best
    }

    /// Index of the next (or previous) screen, ordered left to right then top
    /// to bottom, wrapping around. Nil with a single screen.
    static func adjacentScreen(to index: Int, among screens: [CGRect], forward: Bool) -> Int? {
        guard screens.count > 1 else { return nil }
        let order = screens.indices.sorted { a, b in
            screens[a].minX != screens[b].minX ? screens[a].minX < screens[b].minX : screens[a].maxY > screens[b].maxY
        }
        guard let position = order.firstIndex(of: index) else { return nil }
        return order[(position + (forward ? 1 : -1) + order.count) % order.count]
    }

    static func area(_ rect: CGRect) -> CGFloat {
        rect.isNull ? 0 : rect.width * rect.height
    }
}

extension CGRect {
    /// Rounds each edge to the nearest point, so adjacent layouts (two halves,
    /// three thirds) tile without gaps or overlaps. Unlike `integral`, it never
    /// grows the rect because of floating-point noise.
    var snapped: CGRect {
        let x0 = minX.rounded(), y0 = minY.rounded()
        return CGRect(x: x0, y: y0, width: maxX.rounded() - x0, height: maxY.rounded() - y0)
    }
}
