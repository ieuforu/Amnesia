import SwiftUI

enum LibraryReaderCoordinates {
    static let name = "amnesia-reader-workspace"
}

private struct ReaderSourceFrameKey: PreferenceKey {
    static var defaultValue: CGRect { .null }

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if !next.isNull { value = next }
    }
}

extension View {
    func measureReaderSource(_ update: @escaping (CGRect) -> Void) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(key: ReaderSourceFrameKey.self, value: proxy.frame(in: .named(LibraryReaderCoordinates.name)))
            }
        }
        .onPreferenceChange(ReaderSourceFrameKey.self, perform: update)
    }
}

extension AnyTransition {
    static func readerMorph(from origin: CGRect?) -> AnyTransition {
        .modifier(active: ReaderReveal(progress: 0, origin: origin), identity: ReaderReveal(progress: 1, origin: origin))
    }
}

private struct ReaderReveal: ViewModifier {
    let progress: CGFloat
    let origin: CGRect?

    func body(content: Content) -> some View {
        let reveal = LibraryReaderMorph(progress: progress, origin: origin)
        let textOpacity = min(1, max(0, (progress - 0.20) / 0.58))
        content
            .opacity(textOpacity)
            .background(LibraryAppearance.index)
            .clipShape(reveal)
            .overlay {
                reveal.stroke(LibraryAppearance.accent.opacity(0.36 * (1 - progress)), lineWidth: 1)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
    }
}

/// Reveals the reader from a source frame measured in the mask's local coordinates.
struct LibraryReaderMorph: Shape {
    var progress: CGFloat
    let origin: CGRect?

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        guard !rect.isEmpty else { return Path() }
        let amount = progress.isFinite ? min(1, max(0, progress)) : 1
        guard amount < 1 else { return Path(rect) }

        let localOrigin = origin?.offsetBy(dx: rect.minX, dy: rect.minY).intersection(rect)
        let start: CGRect
        if let localOrigin, !localOrigin.isEmpty,
           localOrigin.width.isFinite, localOrigin.height.isFinite {
            start = localOrigin
        } else {
            start = rect.insetBy(dx: min(16, rect.width * 0.035), dy: min(12, rect.height * 0.03))
        }

        let bounds = CGRect(
            x: interpolate(start.minX, rect.minX, amount),
            y: interpolate(start.minY, rect.minY, amount),
            width: interpolate(start.width, rect.width, amount),
            height: interpolate(start.height, rect.height, amount)
        )
        let startRadius = min(7, start.width / 2, start.height / 2)
        return RoundedRectangle(cornerRadius: startRadius * (1 - amount), style: .continuous).path(in: bounds)
    }

    private func interpolate(_ from: CGFloat, _ to: CGFloat, _ amount: CGFloat) -> CGFloat {
        from + (to - from) * amount
    }
}
