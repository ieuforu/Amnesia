import Foundation
import Testing

@testable import AmnesiaCore

private let claudeID = "aaaaaaaa-0000-4000-8000-000000000001"
private let otherClaudeID = "aaaaaaaa-0000-4000-8000-000000000002"
private let codexID = "bbbbbbbb-0000-7000-8000-000000000001"

private struct TrashFailure: Error {}

/// A throwaway home with a fake Trash, so tests touch neither real sessions
/// nor the real Trash.
private final class Sandbox: @unchecked Sendable {
    let home = FileManager.default.temporaryDirectory
        .appendingPathComponent("amnesia-deleter-\(UUID().uuidString)")
    private let lock = NSLock()
    private(set) var trashed: [String] = []
    private(set) var codexDeletes: [String] = []
    var trashError: Error?
    var codexError: Error?
    var openFiles: Set<String> = []

    deinit { try? FileManager.default.removeItem(at: home) }

    var paths: AgentPaths { AgentPaths(home: home) }
    var recentWriteWindow: TimeInterval = 0

    var deleter: SessionDeleter {
        SessionDeleter(
            paths: paths,
            activity: SessionActivity(
                paths: paths,
                namesOfOpenFiles: { [self] _ in openFiles },
                recentWriteWindow: recentWriteWindow
            ),
            moveToTrash: { [self] url in
                if let trashError { throw trashError }
                try FileManager.default.removeItem(at: url)
                lock.withLock { trashed.append(url.lastPathComponent) }
            },
            deleteCodexSession: { [self] id, _ in
                if let codexError { throw codexError }
                lock.withLock { codexDeletes.append(id) }
                try FileManager.default.removeItem(at: codexFile)
            }
        )
    }

    var claudeFile: URL { url(".claude/projects/-work-app/\(claudeID).jsonl") }
    var codexFile: URL { url(".codex/sessions/2026/11/04/rollout-2026-11-04T08-00-00-\(codexID).jsonl") }
    var claudeHistory: URL { url(".claude/history.jsonl") }
    var codexHistory: URL { url(".codex/history.jsonl") }

    func url(_ path: String) -> URL { home.appendingPathComponent(path) }

    func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: url(path).path)
    }

    func write(_ text: String, to path: String) throws {
        let file = url(path)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try text.write(to: file, atomically: true, encoding: .utf8)
    }

    func makeClaudeSession() throws -> Session {
        try write("{}", to: ".claude/projects/-work-app/\(claudeID).jsonl")
        try write("x", to: ".claude/projects/-work-app/\(claudeID)/subagent.jsonl")
        try write("note", to: ".claude/projects/-work-app/memory/MEMORY.md")
        try write("{}", to: ".claude/projects/-work-app/\(otherClaudeID).jsonl")
        try write("x", to: ".claude/file-history/\(claudeID)/v1")
        try write("x", to: ".claude/file-history/\(otherClaudeID)/v1")
        try write("x", to: ".claude/session-env/\(claudeID)/env")
        try write(
            """
            {"sessionId":"\(claudeID)","display":"secret"}
            {"sessionId":"\(otherClaudeID)","display":"keep"}
            not json
            {"sessionId":"\(claudeID)","display":"secret too"}

            """,
            to: ".claude/history.jsonl"
        )
        return session(claudeID, .claudeCode, claudeFile)
    }

    func makeCodexSession() throws -> Session {
        try write("{}", to: ".codex/sessions/2026/11/04/rollout-2026-11-04T08-00-00-\(codexID).jsonl")
        try write("x", to: ".codex/shell_snapshots/\(codexID).123.sh")
        try write("x", to: ".codex/shell_snapshots/other.123.sh")
        try write(
            """
            {"session_id":"\(codexID)","text":"secret"}
            {"session_id":"other","text":"keep"}

            """,
            to: ".codex/history.jsonl"
        )
        return session(codexID, .codex, codexFile)
    }

    func session(_ id: String, _ source: SessionSource, _ file: URL) -> Session {
        Session(
            id: id, source: source, projectPath: "/work/app", firstMessage: nil,
            updatedAt: Date(), size: 2, fileURL: file, isActive: false
        )
    }
}

@Suite struct ClaudeDeletionTests {
    @Test func trashesTranscriptAndRemovesItsRecords() throws {
        let box = Sandbox()
        let session = try box.makeClaudeSession()

        let result = box.deleter.delete([session])

        #expect(result.map(\.outcome) == [.deleted])
        #expect(box.trashed == ["\(claudeID).jsonl"])
        #expect(!box.exists(".claude/projects/-work-app/\(claudeID)"))
        #expect(!box.exists(".claude/file-history/\(claudeID)"))
        #expect(!box.exists(".claude/session-env/\(claudeID)"))
    }

    @Test func leavesMemoryAndOtherSessionsAlone() throws {
        let box = Sandbox()
        let session = try box.makeClaudeSession()

        _ = box.deleter.delete([session])

        #expect(box.exists(".claude/projects/-work-app/memory/MEMORY.md"))
        #expect(box.exists(".claude/projects/-work-app/\(otherClaudeID).jsonl"))
        #expect(box.exists(".claude/file-history/\(otherClaudeID)/v1"))
    }

    @Test func removesOnlyThatSessionsHistoryLines() throws {
        let box = Sandbox()
        let session = try box.makeClaudeSession()

        _ = box.deleter.delete([session])

        let history = try String(contentsOf: box.claudeHistory, encoding: .utf8)
        #expect(history == "{\"sessionId\":\"\(otherClaudeID)\",\"display\":\"keep\"}\nnot json\n")
    }

    @Test func keepsHistoryFilePrivate() throws {
        let box = Sandbox()
        let session = try box.makeClaudeSession()
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: box.claudeHistory.path)

        _ = box.deleter.delete([session])

        let attributes = try FileManager.default.attributesOfItem(atPath: box.claudeHistory.path)
        #expect(attributes[.posixPermissions] as? Int == 0o600)
    }

    @Test func changesNothingWhenTrashFails() throws {
        let box = Sandbox()
        let session = try box.makeClaudeSession()
        let before = try Data(contentsOf: box.claudeHistory)
        box.trashError = TrashFailure()

        let outcome = box.deleter.delete([session])[0].outcome

        guard case .failed = outcome else {
            Issue.record("Expected a failure, got \(outcome)")
            return
        }
        #expect(box.exists(".claude/file-history/\(claudeID)/v1"))
        #expect(try Data(contentsOf: box.claudeHistory) == before)
    }

    @Test func skipsSessionThatStartedRunning() throws {
        let box = Sandbox()
        let session = try box.makeClaudeSession()
        let pid = ProcessInfo.processInfo.processIdentifier
        try box.write(#"{"sessionId":"\#(claudeID)","pid":\#(pid)}"#, to: ".claude/sessions/\(pid).json")

        #expect(box.deleter.delete([session]).map(\.outcome) == [.skippedInUse])
        #expect(FileManager.default.fileExists(atPath: box.claudeFile.path))
        #expect(box.trashed.isEmpty)
    }

    @Test func skipsSessionWrittenMomentsAgo() throws {
        let box = Sandbox()
        let session = try box.makeClaudeSession()
        box.recentWriteWindow = 120

        #expect(box.deleter.delete([session]).map(\.outcome) == [.skippedInUse])
        #expect(FileManager.default.fileExists(atPath: box.claudeFile.path))
    }

    @Test func refusesFilesOutsideClaudeProjects() throws {
        let box = Sandbox()
        try box.write("precious", to: "Documents/\(claudeID).jsonl")
        let session = box.session(claudeID, .claudeCode, box.url("Documents/\(claudeID).jsonl"))

        let outcome = box.deleter.delete([session])[0].outcome

        guard case .failed = outcome else {
            Issue.record("Expected a refusal, got \(outcome)")
            return
        }
        #expect(box.exists("Documents/\(claudeID).jsonl"))
    }
}

@Suite struct CodexDeletionTests {
    @Test func usesCLIThenTrashesCopyAndCleansLeftovers() throws {
        let box = Sandbox()
        let session = try box.makeCodexSession()

        let result = box.deleter.delete([session])

        #expect(result.map(\.outcome) == [.deleted])
        #expect(box.codexDeletes == [codexID])
        #expect(box.trashed == [session.fileURL.lastPathComponent])
        #expect(!box.exists(".codex/shell_snapshots/\(codexID).123.sh"))
        #expect(box.exists(".codex/shell_snapshots/other.123.sh"))
        let history = try String(contentsOf: box.codexHistory, encoding: .utf8)
        #expect(history == "{\"session_id\":\"other\",\"text\":\"keep\"}\n")
    }

    @Test func skipsCLIWhenTrashFails() throws {
        let box = Sandbox()
        let session = try box.makeCodexSession()
        box.trashError = TrashFailure()

        let outcome = box.deleter.delete([session])[0].outcome

        guard case .failed = outcome else {
            Issue.record("Expected a failure, got \(outcome)")
            return
        }
        #expect(box.codexDeletes.isEmpty)
        #expect(FileManager.default.fileExists(atPath: box.codexFile.path))
    }

    @Test func keepsSessionWhenCLIFails() throws {
        let box = Sandbox()
        let session = try box.makeCodexSession()
        let before = try Data(contentsOf: box.codexHistory)
        box.codexError = CodexCLIError.deleteFailed

        let outcome = box.deleter.delete([session])[0].outcome

        #expect(outcome == .failed("The codex command couldn't delete it."))
        #expect(FileManager.default.fileExists(atPath: box.codexFile.path))
        #expect(box.exists(".codex/shell_snapshots/\(codexID).123.sh"))
        #expect(try Data(contentsOf: box.codexHistory) == before)
    }

    @Test func skipsSessionWithOpenLock() throws {
        let box = Sandbox()
        let session = try box.makeCodexSession()
        try box.write("", to: ".codex/thread-writer-locks/\(codexID).lock")
        box.openFiles = ["\(codexID).lock"]

        #expect(box.deleter.delete([session]).map(\.outcome) == [.skippedInUse])
        #expect(box.codexDeletes.isEmpty)
    }

    @Test func skipsSessionWithOpenTranscript() throws {
        let box = Sandbox()
        let session = try box.makeCodexSession()
        box.openFiles = [session.fileURL.lastPathComponent]

        #expect(box.deleter.delete([session]).map(\.outcome) == [.skippedInUse])
        #expect(box.trashed.isEmpty)
    }

    @Test func refusesFilesOutsideCodexSessions() throws {
        let box = Sandbox()
        try box.write("precious", to: ".codex/config-\(codexID).jsonl")
        let session = box.session(codexID, .codex, box.url(".codex/config-\(codexID).jsonl"))

        let outcome = box.deleter.delete([session])[0].outcome

        guard case .failed = outcome else {
            Issue.record("Expected a refusal, got \(outcome)")
            return
        }
        #expect(box.codexDeletes.isEmpty)
    }
}

@Suite struct HistoryFileTests {
    @Test func leavesFileUntouchedWhenNothingMatches() throws {
        let box = Sandbox()
        try box.write("{\"sessionId\":\"other\"}\n", to: "history.jsonl")
        let url = box.url("history.jsonl")
        let before = try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date

        try HistoryFile.removeEntries(at: url, forKey: "sessionId", values: ["missing"])

        let after = try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
        #expect(before == after)
    }

    @Test func ignoresMissingFile() throws {
        let box = Sandbox()
        try HistoryFile.removeEntries(at: box.url("none.jsonl"), forKey: "k", values: ["v"])
    }
}
