import Foundation
import SQLite3
import Testing

@testable import AmnesiaCore

private let goneID = "cccccccc-0000-4000-8000-000000000001"
private let liveID = "cccccccc-0000-4000-8000-000000000002"
private let recentID = "cccccccc-0000-4000-8000-000000000003"
private let threadID = "dddddddd-0000-7000-8000-000000000001"

private final class LeftoverSandbox: @unchecked Sendable {
    let home = FileManager.default.temporaryDirectory
        .appendingPathComponent("amnesia-leftovers-\(UUID().uuidString)")
    private let lock = NSLock()
    private(set) var codexDeletes: [String] = []
    var codexError: Error?
    var openFiles: Set<String> = []

    deinit { try? FileManager.default.removeItem(at: home) }

    private var paths: AgentPaths { AgentPaths(home: home) }

    private var activity: SessionActivity {
        SessionActivity(paths: paths, namesOfOpenFiles: { [self] _ in openFiles }, recentWriteWindow: 0)
    }

    var cleaner: LeftoverCleaner {
        LeftoverCleaner(
            paths: paths,
            activity: activity,
            minimumAge: 3600,
            deleteCodexSession: { [self] id, _ in
                if let codexError { throw codexError }
                lock.withLock { codexDeletes.append(id) }
            }
        )
    }

    func url(_ path: String) -> URL { home.appendingPathComponent(path) }

    func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: url(path).path)
    }

    func write(_ text: String, to path: String, age: TimeInterval = 7200) throws {
        let file = url(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: file, atomically: true, encoding: .utf8)
        try backdate(file, by: age)
    }

    private func backdate(_ file: URL, by seconds: TimeInterval) throws {
        let date = Date(timeIntervalSinceNow: -seconds)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: file.path)
        try FileManager.default.setAttributes(
            [.modificationDate: date],
            ofItemAtPath: file.deletingLastPathComponent().path
        )
    }

    func scan() -> [Leftover] {
        LeftoverScanner(paths: paths, activity: activity, minimumAge: 3600)
            .scan(excluding: SessionScanner(paths: paths, activity: activity).scan())
    }

    func makeClaudeLeftovers() throws {
        let old = Date(timeIntervalSinceNow: -7200).timeIntervalSince1970 * 1000
        let now = Date().timeIntervalSince1970 * 1000
        try write(
            """
            {"sessionId":"\(goneID)","display":"old prompt","timestamp":\(old)}
            {"sessionId":"\(goneID)","display":"old prompt 2","timestamp":\(old)}
            {"sessionId":"\(liveID)","display":"keep","timestamp":\(old)}
            {"sessionId":"\(recentID)","display":"just started","timestamp":\(now)}
            {"sessionId":"not-a-uuid","display":"keep","timestamp":\(old)}

            """,
            to: ".claude/history.jsonl"
        )
        try write("x", to: ".claude/file-history/\(goneID)/v1")
        try write("x", to: ".claude/session-env/\(goneID)/env")
        try write("x", to: ".claude/file-history/\(liveID)/v1")
        try write("{}", to: ".claude/projects/-work/\(liveID).jsonl")
        try write("note", to: ".claude/projects/-work/memory/MEMORY.md")
        try write("x", to: ".claude/file-history/unrelated/v1")
    }

    func makeThreadsDatabase(rolloutPath: String, updatedAt: Int) throws {
        try FileManager.default.createDirectory(at: url(".codex"), withIntermediateDirectories: true)
        var database: OpaquePointer?
        defer { sqlite3_close(database) }
        #expect(sqlite3_open(url(".codex/state_5.sqlite").path, &database) == SQLITE_OK)
        let sql = """
            CREATE TABLE threads (id TEXT PRIMARY KEY, rollout_path TEXT, updated_at INTEGER);
            INSERT INTO threads VALUES ('\(threadID)', '\(rolloutPath)', \(updatedAt));
            """
        #expect(sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK)
    }
}

@Suite struct LeftoverScanTests {
    @Test func findsRecordsWithoutATranscript() throws {
        let box = LeftoverSandbox()
        try box.makeClaudeLeftovers()

        let leftovers = box.scan()

        #expect(leftovers.map(\.id) == [goneID])
        #expect(leftovers[0].source == .claudeCode)
        #expect(leftovers[0].promptCount == 2)
        #expect(leftovers[0].files.count == 2)
        #expect(leftovers[0].size > 0)
    }

    @Test func ignoresRecentActivity() throws {
        let box = LeftoverSandbox()
        try box.write("x", to: ".claude/session-env/\(recentID)/env", age: 60)

        #expect(box.scan().isEmpty)
    }

    @Test func ignoresRunningClaudeSessionWithoutTranscript() throws {
        let box = LeftoverSandbox()
        try box.write("x", to: ".claude/session-env/\(goneID)/env")
        let pid = ProcessInfo.processInfo.processIdentifier
        try box.write(#"{"sessionId":"\#(goneID)","pid":\#(pid)}"#, to: ".claude/sessions/\(pid).json")

        #expect(box.scan().isEmpty)
    }

    @Test func findsCodexHistoryAndSnapshots() throws {
        let box = LeftoverSandbox()
        let old = Int(Date(timeIntervalSinceNow: -7200).timeIntervalSince1970)
        try box.write(#"{"session_id":"\#(threadID)","ts":\#(old),"text":"x"}"#, to: ".codex/history.jsonl")
        try box.write("x", to: ".codex/shell_snapshots/\(threadID).123.sh")
        try box.write("x", to: ".codex/shell_snapshots/not-a-session.sh")

        let leftovers = box.scan()

        #expect(leftovers.map(\.id) == [threadID])
        #expect(leftovers[0].source == .codex)
        #expect(leftovers[0].files.map(\.lastPathComponent) == ["\(threadID).123.sh"])
    }

    @Test func findsOrphanedThreadRecord() throws {
        let box = LeftoverSandbox()
        let old = Int(Date(timeIntervalSinceNow: -7200).timeIntervalSince1970)
        try box.makeThreadsDatabase(rolloutPath: "/missing/rollout.jsonl", updatedAt: old)

        #expect(box.scan().first?.hasDatabaseRecord == true)
    }

    @Test func ignoresThreadWhoseTranscriptExists() throws {
        let box = LeftoverSandbox()
        let old = Int(Date(timeIntervalSinceNow: -7200).timeIntervalSince1970)
        try box.write("{}", to: "rollout.jsonl")
        try box.makeThreadsDatabase(rolloutPath: box.url("rollout.jsonl").path, updatedAt: old)

        #expect(box.scan().isEmpty)
    }

    @Test func ignoresCodexSessionWithOpenLock() throws {
        let box = LeftoverSandbox()
        try box.write("x", to: ".codex/shell_snapshots/\(threadID).123.sh")
        try box.write("", to: ".codex/thread-writer-locks/\(threadID).lock")
        box.openFiles = ["\(threadID).lock"]

        #expect(box.scan().isEmpty)
    }

    @Test func unreadableDatabaseYieldsNothing() throws {
        let box = LeftoverSandbox()
        try box.write("not a database", to: ".codex/state_5.sqlite")

        #expect(box.scan().isEmpty)
    }
}

@Suite struct LeftoverCleanTests {
    @Test func removesLeftoversAndNothingElse() throws {
        let box = LeftoverSandbox()
        try box.makeClaudeLeftovers()

        let failures = box.cleaner.clean(box.scan())

        #expect(failures == 0)
        #expect(!box.exists(".claude/file-history/\(goneID)"))
        #expect(!box.exists(".claude/session-env/\(goneID)"))
        #expect(box.exists(".claude/file-history/\(liveID)/v1"))
        #expect(box.exists(".claude/file-history/unrelated/v1"))
        #expect(box.exists(".claude/projects/-work/\(liveID).jsonl"))
        #expect(box.exists(".claude/projects/-work/memory/MEMORY.md"))

        let history = try String(contentsOf: box.url(".claude/history.jsonl"), encoding: .utf8)
        #expect(!history.contains("old prompt"))
        #expect(history.contains(liveID))
        #expect(history.contains(recentID))
        #expect(history.contains("not-a-uuid"))
    }

    @Test func skipsSessionThatCameBackAfterScanning() throws {
        let box = LeftoverSandbox()
        try box.makeClaudeLeftovers()
        let stale = box.scan()
        try box.write("{}", to: ".claude/projects/-work/\(goneID).jsonl")

        #expect(box.cleaner.clean(stale) == 0)
        #expect(box.exists(".claude/file-history/\(goneID)/v1"))
    }

    @Test func clearsDatabaseRecordsThroughCLI() throws {
        let box = LeftoverSandbox()
        let old = Int(Date(timeIntervalSinceNow: -7200).timeIntervalSince1970)
        try box.makeThreadsDatabase(rolloutPath: "/missing/rollout.jsonl", updatedAt: old)

        #expect(box.cleaner.clean(box.scan()) == 0)
        #expect(box.codexDeletes == [threadID])
    }

    @Test func keepsRecordsWhenCLIFails() throws {
        let box = LeftoverSandbox()
        let old = Int(Date(timeIntervalSinceNow: -7200).timeIntervalSince1970)
        try box.makeThreadsDatabase(rolloutPath: "/missing/rollout.jsonl", updatedAt: old)
        try box.write(#"{"session_id":"\#(threadID)","ts":\#(old),"text":"x"}"#, to: ".codex/history.jsonl")
        try box.write("x", to: ".codex/shell_snapshots/\(threadID).123.sh")
        box.codexError = CodexCLIError.deleteFailed

        #expect(box.cleaner.clean(box.scan()) == 1)
        #expect(box.exists(".codex/shell_snapshots/\(threadID).123.sh"))
        #expect(try String(contentsOf: box.url(".codex/history.jsonl"), encoding: .utf8).contains(threadID))
    }
}
