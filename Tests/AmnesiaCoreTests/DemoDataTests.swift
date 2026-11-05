import Foundation
import Testing

@testable import AmnesiaCore

@Suite struct DemoDataTests {
    @Test func coversEveryAgentAndAnInUseSession() {
        let sessions = DemoData.sessions()

        for source in SessionSource.allCases {
            let own = sessions.filter { $0.source == source }
            #expect(own.count > 1)
            #expect(own.contains { $0.isActive })
            #expect(DemoData.leftovers().contains { $0.source == source })
        }
    }

    @Test func idsAreUniqueValidUUIDs() {
        let ids = DemoData.sessions().map(\.id) + DemoData.leftovers().map(\.id)

        #expect(Set(ids).count == ids.count)
        #expect(ids.allSatisfy { UUID(uuidString: $0) != nil })
    }

    @Test func neverReferencesTheRealHomeDirectory() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let paths = DemoData.sessions().flatMap { [$0.projectPath ?? "", $0.fileURL.path] }

        #expect(!paths.contains { $0.hasPrefix(home) })
        #expect(DemoData.leftovers().allSatisfy { $0.files.isEmpty })
    }

    @Test func realDeleterRefusesDemoSessions() {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("amnesia-demo-\(UUID().uuidString)")

        let outcomes = SessionDeleter(homeDirectory: home).delete(DemoData.sessions()).map(\.outcome)

        #expect(outcomes.allSatisfy { $0 != .deleted })
    }
}
