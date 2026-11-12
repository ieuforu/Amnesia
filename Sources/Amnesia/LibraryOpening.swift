import Observation
import SwiftUI

@MainActor
@Observable
final class LibraryOpening {
    private var hasPresented = false
    private(set) var sequence: UUID?

    func presentFirstTime() {
        guard !hasPresented else { return }
        hasPresented = true
        replay()
    }

    func replay() { sequence = UUID() }

    func dismiss(_ completed: UUID) {
        if sequence == completed { sequence = nil }
    }
}

struct LibraryOpeningView: View {
    let dismiss: () -> Void

    @State private var began = Date.now

    private static let duration = 0.65
    private static let markSize = CGSize(width: 84, height: 64)
    private static let stencil = [
        ".xxxx.",
        "xxxx.x",
        "xxxx.x",
        "xxxxx.",
        ".xx...",
        ".x....",
    ]

    var body: some View {
        Button(action: dismiss) {
            TimelineView(.animation) { tick in
                let elapsed = max(0, tick.date.timeIntervalSince(began))
                scene(elapsed: elapsed)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Skip Amnesia opening")
        .onExitCommand(perform: dismiss)
        .task {
            try? await Task.sleep(for: .seconds(Self.duration))
            if !Task.isCancelled { dismiss() }
        }
    }

    private func scene(elapsed: Double) -> some View {
        let word = smooth(elapsed, from: 0.19, to: 0.36)
        let reveal = smooth(elapsed, from: 0.43, to: Self.duration - 0.01)
        return ZStack {
            Rectangle().fill(LibraryAppearance.paper)
            VStack(spacing: 0) {
                LibraryOpeningParticles(dots: Self.mark, animationID: 0)
                    .frame(width: Self.markSize.width, height: Self.markSize.height)
                Text("Amnesia")
                    .font(.system(size: 25, weight: .semibold)).tracking(-0.65)
                    .foregroundStyle(LibraryAppearance.ink)
                    .offset(y: 3 * (1 - word))
                    .opacity(word)
            }
            .fixedSize()
        }
        .opacity(1 - reveal)
        .accessibilityHidden(true)
    }

    private static let mark: [LibraryOpeningDot] = stencil.enumerated().flatMap { row, line in
        line.enumerated().compactMap { column, symbol in
            guard symbol == "x" else { return nil }
            return LibraryOpeningDot(
                position: CGPoint(
                    x: markSize.width / 2 + (Double(column) - 2.5) * 6,
                    y: markSize.height / 2 + (Double(row) - 2.5) * 6
                ),
                isClaude: column >= 4
            )
        }
    }

    private func smooth(_ time: Double, from start: Double, to end: Double) -> Double {
        let value = min(1, max(0, (time - start) / (end - start)))
        return value * value * (3 - 2 * value)
    }
}
