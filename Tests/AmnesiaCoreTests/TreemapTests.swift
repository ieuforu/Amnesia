import CoreGraphics
import Foundation
import Testing

@testable import AmnesiaCore

@Suite struct TreemapTests {
    private let bounds = CGRect(x: 0, y: 0, width: 1000, height: 600)

    private func items(_ values: [Double]) -> [Treemap.Item] {
        values.enumerated().map { Treemap.Item(id: "\($0)", value: $1) }
    }

    @Test func areasMatchValues() throws {
        let values: [Double] = [50, 25, 15, 7, 3]
        let rects = Treemap.layout(items(values), in: bounds)
        let total = values.reduce(0, +)

        for (index, value) in values.enumerated() {
            let rect = try #require(rects["\(index)"])
            let expected = bounds.width * bounds.height * value / total
            #expect(abs(rect.width * rect.height - expected) < 1)
        }
    }

    @Test func staysInsideWithoutOverlapping() {
        let rects = Array(Treemap.layout(items([9, 8, 7, 6, 5, 4, 3, 2, 1]), in: bounds).values)

        for (index, rect) in rects.enumerated() {
            #expect(bounds.insetBy(dx: -0.01, dy: -0.01).contains(rect))
            for other in rects[(index + 1)...] {
                let overlap = rect.intersection(other)
                #expect(overlap.isNull || overlap.width * overlap.height < 0.01)
            }
        }
    }

    @Test func skipsEmptyValuesAndHandlesNoData() {
        #expect(Treemap.layout(items([0, 0]), in: bounds).isEmpty)
        #expect(Treemap.layout(items([5, 0]), in: bounds).count == 1)
        #expect(Treemap.layout(items([5]), in: .zero).isEmpty)
    }

    @Test func oneItemFillsTheSpace() {
        #expect(Treemap.layout(items([5]), in: bounds)["0"] == bounds)
    }
}

@Suite struct FadeTests {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    private func session(daysAgo: Double) -> Session {
        Session(
            id: UUID().uuidString,
            source: .codex,
            projectPath: "/work",
            firstMessage: nil,
            updatedAt: now.addingTimeInterval(-daysAgo * 24 * 60 * 60),
            size: 1,
            fileURL: URL(fileURLWithPath: "/work/x.jsonl"),
            isActive: false
        )
    }

    @Test func runsFromRecentToForgotten() {
        #expect(session(daysAgo: 0).fade(now: now) == 0)
        #expect(session(daysAgo: 90).fade(now: now) == 1)
        #expect(session(daysAgo: 400).fade(now: now) == 1)
        #expect(session(daysAgo: 7).fade(now: now) < session(daysAgo: 30).fade(now: now))
    }

    @Test func aProjectIsAsRememberedAsItsNewestSession() throws {
        let group = try #require(SessionGroup.grouping([session(daysAgo: 1), session(daysAgo: 80)]).first)
        #expect(group.fade(now: now) == session(daysAgo: 1).fade(now: now))
    }
}
