import AppKit
import SwiftUI

enum LibraryAppearance {
    static let chrome = adaptive(0xE0E8F5, 0x1B2536)
    static let index = adaptive(0xF9FBFF, 0x172133)
    static let paper = adaptive(0xEEF3FA, 0x111927)
    static let rule = adaptive(0xCFDAE9, 0x334257)
    static let ink = adaptive(0x142035, 0xEAF2FF)
    static let muted = adaptive(0x52637D, 0xA9B8CF)
    static let accent = adaptive(0x2454BD, 0x83AAFF)
    static let claude = adaptive(0x00745E, 0x7FE0BE)
    static let selection = adaptive(0xDCE8FB, 0x263D64)

    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(
                srgbRed: CGFloat((hex >> 16) & 255) / 255,
                green: CGFloat((hex >> 8) & 255) / 255,
                blue: CGFloat(hex & 255) / 255,
                alpha: 1
            )
        })
    }
}

struct LibraryButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 9)
            .frame(minHeight: 28)
            .foregroundStyle(prominent ? LibraryAppearance.accent : LibraryAppearance.ink)
            .background(prominent ? LibraryAppearance.selection : LibraryAppearance.index, in: RoundedRectangle(cornerRadius: 6))
            .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(LibraryAppearance.rule) }
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.45)
    }
}

struct LibraryDotMark: View {
    var body: some View {
        Canvas { context, size in
            let unit = size.width / 5
            for row in 0..<5 {
                for column in 0..<5 where abs(row - 2) + abs(column - 2) <= 3 {
                    let distance = abs(row - 2) + abs(column - 2)
                    let diameter = unit * (distance < 2 ? 0.74 : 0.47)
                    let x = (CGFloat(column) + 0.5) * unit - diameter / 2
                    let y = (CGFloat(row) + 0.5) * unit - diameter / 2
                    let path = Path(ellipseIn: CGRect(x: x, y: y, width: diameter, height: diameter))
                    context.fill(path, with: .color(LibraryAppearance.accent.opacity(distance < 3 ? 1 : 0.45)))
                }
            }
        }
        .accessibilityHidden(true)
    }
}
