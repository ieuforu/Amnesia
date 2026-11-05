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
