import SwiftUI

/// Breaks a view into pieces that drift away as dots, sweeping left to right
/// like the speech bubble in the app icon.
struct Shredded<Content: View>: View {
    static var duration: TimeInterval { 0.8 }

    @ViewBuilder let content: Content

    @State private var start = Date()

    var body: some View {
        TimelineView(.animation) { timeline in
            ShredFrame(
                progress: min(1, timeline.date.timeIntervalSince(start) / Self.duration),
                content: content
            )
        }
    }
}

/// One moment of the effect, separate so it can be drawn at a chosen progress.
struct ShredFrame<Content: View>: View {
    let progress: Double
    let content: Content

    /// Room around the view for pieces to fly into.
    private static var margin: CGFloat { 70 }
    private static var pieceSize: CGFloat { 8 }
    /// How much of the timeline the left-to-right sweep takes.
    private static var sweep: Double { 0.55 }

    var body: some View {
        content
            .hidden()
            .overlay {
                GeometryReader { geometry in
                    Canvas(rendersAsynchronously: false) { context, size in
                        guard let source = context.resolveSymbol(id: 0) else { return }
                        draw(source, in: context, canvasSize: size)
                    } symbols: {
                        // Pinned to the view's own size, because a symbol would
                        // otherwise stretch to fill the larger canvas.
                        content
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .tag(0)
                    }
                    .padding(-Self.margin)
                }
                .allowsHitTesting(false)
            }
    }

    private func draw(
        _ source: GraphicsContext.ResolvedSymbol,
        in context: GraphicsContext,
        canvasSize: CGSize
    ) {
        let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        let width = canvasSize.width - Self.margin * 2
        let height = canvasSize.height - Self.margin * 2
        let columns = Int((width / Self.pieceSize).rounded(.up))
        let rows = Int((height / Self.pieceSize).rounded(.up))

        // Pieces that haven't moved are drawn as one shape, because the card is
        // translucent and overlapping pieces would show as a grid.
        var whole = Path()

        for column in 0..<columns {
            for row in 0..<rows {
                let along = Double(column) / Double(max(columns - 1, 1))
                let jitter = Self.random(column, row, 1)
                let begin = along * Self.sweep + jitter * 0.12
                let span = 1 - Self.sweep - 0.12
                let local = min(max((progress - begin) / span, 0), 1)
                guard local < 1 else { continue }

                let cell = CGRect(
                    x: Self.margin + CGFloat(column) * Self.pieceSize,
                    y: Self.margin + CGFloat(row) * Self.pieceSize,
                    width: Self.pieceSize,
                    height: Self.pieceSize
                )
                guard local > 0 else {
                    whole.addRect(cell)
                    continue
                }

                let eased = local * local
                let shrink = 1 - 0.75 * local
                let piece = cell.insetBy(
                    dx: cell.width * (1 - shrink) / 2,
                    dy: cell.height * (1 - shrink) / 2
                )

                var layer = context
                layer.opacity = 1 - eased * eased
                layer.translateBy(
                    x: CGFloat(eased) * (28 + 44 * Self.random(column, row, 2)),
                    y: CGFloat(eased) * (-26 + 40 * Self.random(column, row, 3))
                )
                layer.clip(
                    to: Path(roundedRect: piece, cornerRadius: piece.width / 2 * min(local * 3, 1))
                )
                layer.draw(source, at: center)
            }
        }

        var layer = context
        layer.clip(to: whole)
        layer.draw(source, at: center)
    }

    /// Stable noise, so a piece keeps its path from frame to frame.
    private static func random(_ column: Int, _ row: Int, _ salt: Int) -> Double {
        let value = sin(Double(column) * 12.9898 + Double(row) * 78.233 + Double(salt) * 37.719) * 43758.5453
        return value - value.rounded(.down)
    }
}

/// A trash can with a lid that lifts, which an SF Symbol can't do.
struct TrashCan: View {
    let isOpen: Bool
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Capsule()
                .fill(color)
                .frame(width: 34, height: 2.5)
                .overlay(alignment: .top) {
                    UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3)
                        .stroke(color, lineWidth: 2)
                        .frame(width: 11, height: 4)
                        .offset(y: -4)
                }
                .rotationEffect(.degrees(isOpen ? -22 : 0), anchor: .trailing)
                .offset(y: isOpen ? -3 : 0)

            UnevenRoundedRectangle(bottomLeadingRadius: 5, bottomTrailingRadius: 5)
                .stroke(color, lineWidth: 2)
                .frame(width: 26, height: 30)
                .overlay {
                    HStack(spacing: 5) {
                        ForEach(0..<2, id: \.self) { _ in
                            Capsule()
                                .fill(color.opacity(0.75))
                                .frame(width: 2, height: 17)
                        }
                    }
                }
        }
        .frame(width: 40, height: 46)
        .accessibilityHidden(true)
    }
}
