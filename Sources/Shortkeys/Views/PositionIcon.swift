import SwiftUI

/// Small blue tile showing where a window command puts the window.
struct PositionIcon: View {
    let command: WindowCommand

    var body: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(Color.blue.gradient)
            .overlay { glyph.padding(4) }
            .frame(width: 22, height: 22)
    }

    @ViewBuilder private var glyph: some View {
        if let rect = iconRect {
            // The screen, with the command's area highlighted.
            Canvas { context, size in
                let screen = CGRect(origin: .zero, size: size)
                let area = CGRect(
                    x: rect.minX * size.width, y: rect.minY * size.height,
                    width: rect.width * size.width, height: rect.height * size.height
                )
                context.fill(Path(roundedRect: screen, cornerRadius: 1.5), with: .color(.white.opacity(0.35)))
                context.fill(Path(roundedRect: area, cornerRadius: 1.5), with: .color(.white))
            }
        } else {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
        }
    }

    private var iconRect: CGRect? {
        switch command {
        case .center: CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6)
        case .maximizeWidth: CGRect(x: 0, y: 0.3, width: 1, height: 0.4)
        case .maximizeHeight: CGRect(x: 0.3, y: 0, width: 0.4, height: 1)
        default: command.unitRect
        }
    }

    private var symbol: String {
        switch command {
        case .restore: "arrow.uturn.backward"
        case .makeLarger: "plus"
        case .makeSmaller: "minus"
        case .toggleFullscreen: "arrow.up.left.and.arrow.down.right"
        case .moveUp: "arrow.up"
        case .moveDown: "arrow.down"
        case .moveLeft: "arrow.left"
        case .moveRight: "arrow.right"
        case .nextDisplay: "chevron.right.2"
        case .previousDisplay: "chevron.left.2"
        default: "macwindow"
        }
    }
}

/// Colored rounded-square icon for sidebar rows, as in System Settings.
struct SidebarIcon: View {
    let systemName: String
    let color: Color

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}
