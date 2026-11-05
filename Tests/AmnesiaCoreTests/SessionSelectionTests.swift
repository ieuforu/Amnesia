import Foundation
import Testing

@testable import AmnesiaCore

private let now = Date(timeIntervalSince1970: 2_000_000_000)
private let day: TimeInterval = 24 * 60 * 60

private func session(_ id: String, age: TimeInterval = 0, isActive: Bool = false) -> Session {
    Session(
        id: id,
        source: .claudeCode,
        projectPath: "/work/app",
        firstMessage: nil,
        updatedAt: now.addingTimeInterval(-age),
        size: 1,
        fileURL: URL(fileURLWithPath: "/work/\(id).jsonl"),
        isActive: isActive
    )
}

@Suite struct SessionSelectionTests {
    @Test func ageComparisonIsStrict() {
        #expect(session("a", age: 31 * day).isOlder(thanDays: 30, now: now))
        #expect(!session("b", age: 30 * day).isOlder(thanDays: 30, now: now))
        #expect(!session("c", age: 29 * day).isOlder(thanDays: 30, now: now))
    }

    @Test func sessionsInUseAreNeverDeletable() {
        #expect(session("idle").isDeletable)
        #expect(!session("running", isActive: true).isDeletable)
    }

    @Test func groupSelectionSkipsSessionsInUse() throws {
        let sessions = [session("idle"), session("running", isActive: true), session("old", age: 90 * day)]

        let group = try #require(SessionGroup.grouping(sessions).first)

        #expect(group.deletableIDs == ["idle", "old"])
    }

    @Test func groupWithOnlySessionsInUseHasNothingToSelect() throws {
        let group = try #require(SessionGroup.grouping([session("running", isActive: true)]).first)

        #expect(group.deletableIDs.isEmpty)
    }
}

@Suite struct SessionGroupNamingTests {
    @Test func namesComeFromTheProjectFolder() {
        #expect(SessionGroup(projectPath: "/work/app", sessions: []).displayName == "app")
        #expect(SessionGroup(projectPath: NSHomeDirectory(), sessions: []).displayName == "Home")
        #expect(SessionGroup(projectPath: nil, sessions: []).displayName == "Unknown Project")
    }
}

@Suite struct ListSelectionTests {
    private let rows = ["a", "b", "c", "d"]

    @Test func plainClickReplacesTheSelection() {
        var selection = ListSelection(ids: ["a", "b"])
        selection.click("c", .plain, in: rows)
        #expect(selection.ids == ["c"])
    }

    @Test func commandClickToggles() {
        var selection = ListSelection()
        selection.click("a", .toggle, in: rows)
        selection.click("c", .toggle, in: rows)
        selection.click("a", .toggle, in: rows)
        #expect(selection.ids == ["c"])
    }

    @Test func shiftClickSelectsTheRangeInEitherDirection() {
        var selection = ListSelection()
        selection.click("c", .plain, in: rows)
        selection.click("a", .extend, in: rows)
        #expect(selection.ids == ["a", "b", "c"])
        selection.click("d", .extend, in: rows)
        #expect(selection.ids == ["c", "d"])
    }

    @Test func arrowKeysMoveAndStopAtTheEnds() {
        var selection = ListSelection()
        selection.move(by: 1, in: rows)
        #expect(selection.ids == ["a"])
        selection.move(by: 1, in: rows)
        #expect(selection.ids == ["b"])
        selection.click("d", .plain, in: rows)
        selection.move(by: 1, in: rows)
        #expect(selection.ids == ["d"])
    }

    @Test func limitDropsRowsThatAreGone() {
        var selection = ListSelection()
        selection.click("a", .plain, in: rows)
        selection.click("b", .toggle, in: rows)
        selection.limit(to: ["b", "c"])
        #expect(selection.ids == ["b"])
    }
}
