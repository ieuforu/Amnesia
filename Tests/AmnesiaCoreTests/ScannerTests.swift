import Foundation
import Testing

@testable import AmnesiaCore

/// A throwaway home directory, so tests never touch real sessions.
private struct FakeHome {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("amnesia-tests-\(UUID().uuidString)")

    func write(_ lines: [String], to path: String) throws {
        let file = url.appendingPathComponent(path)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}

private let claudeID = "aaaaaaaa-0000-4000-8000-000000000001"
private let codexID = "bbbbbbbb-0000-7000-8000-000000000002"

@Suite struct ClaudeScannerTests {
    private func scan(_ home: FakeHome) -> [Session] {
        ClaudeSessionScanner(claudeHome: home.url.appendingPathComponent(".claude")).scan()
    }

    @Test func readsProjectAndFirstTypedMessage() throws {
        let home = FakeHome()
        defer { home.remove() }
        try home.write(
            [
                #"{"type":"mode"}"#,
                #"{"type":"user","cwd":"/work/app","isMeta":true,"message":{"content":"injected"}}"#,
                #"{"type":"user","cwd":"/work/app","message":{"content":"<command-name>/clear</command-name>"}}"#,
                #"{"type":"user","cwd":"/work/app","isSidechain":true,"message":{"content":"subagent"}}"#,
                #"{"type":"user","cwd":"/work/app","message":{"content":"fix the\n  login bug"}}"#,
            ],
            to: ".claude/projects/-work-app/\(claudeID).jsonl"
        )

        let session = try #require(scan(home).first)
        #expect(session.id == claudeID)
        #expect(session.source == .claudeCode)
        #expect(session.projectPath == "/work/app")
        #expect(session.firstMessage == "fix the login bug")
        #expect(!session.isActive)
    }

    @Test func readsTextBlocksFromArrayContent() throws {
        let home = FakeHome()
        defer { home.remove() }
        try home.write(
            [
                #"{"type":"user","message":{"content":[{"type":"image"},{"type":"text","text":"what is this"}]}}"#
            ],
            to: ".claude/projects/-work-app/\(claudeID).jsonl"
        )

        #expect(scan(home).first?.firstMessage == "what is this")
    }

    @Test func usesLatestRenameEvenInLongTranscripts() throws {
        let home = FakeHome()
        defer { home.remove() }
        let padding = String(repeating: "x", count: 300 * 1024)
        try home.write(
            [
                #"{"type":"user","cwd":"/work/app","message":{"content":"hello"}}"#,
                #"{"type":"custom-title","customTitle":"first name"}"#,
                #"{"type":"assistant","text":"\#(padding)"}"#,
                #"{"type":"custom-title","customTitle":"second name"}"#,
                #"{"type":"custom-title","customTitle":"final name"}"#,
                #"{"type":"assistant","text":"done"}"#,
            ],
            to: ".claude/projects/-work-app/\(claudeID).jsonl"
        )

        let session = try #require(scan(home).first)
        #expect(session.name == "final name")
        #expect(session.firstMessage == "hello")
    }

    @Test func hasNoNameUntilRenamed() throws {
        let home = FakeHome()
        defer { home.remove() }
        try home.write(
            [
                #"{"type":"user","message":{"content":"hello"}}"#,
                #"{"type":"ai-title","aiTitle":"generated"}"#,
            ],
            to: ".claude/projects/-work-app/\(claudeID).jsonl"
        )

        #expect(scan(home).first?.name == nil)
    }

    @Test func ignoresMemoryAndNonSessionFiles() throws {
        let home = FakeHome()
        defer { home.remove() }
        try home.write(["{}"], to: ".claude/projects/-work-app/memory/MEMORY.md")
        try home.write(["{}"], to: ".claude/projects/-work-app/agent-1234.jsonl")

        #expect(scan(home).isEmpty)
    }

    @Test func marksSessionActiveOnlyWhileItsProcessRuns() throws {
        let home = FakeHome()
        defer { home.remove() }
        let liveID = "aaaaaaaa-0000-4000-8000-000000000003"
        for id in [claudeID, liveID] {
            try home.write(["{}"], to: ".claude/projects/-work-app/\(id).jsonl")
        }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        try home.write(
            [#"{"sessionId":"\#(liveID)","pid":\#(ownPID)}"#],
            to: ".claude/sessions/\(ownPID).json"
        )
        try home.write(
            [#"{"sessionId":"\#(claudeID)","pid":2147483646}"#],
            to: ".claude/sessions/2147483646.json"
        )

        let active = scan(home).filter(\.isActive).map(\.id)
        #expect(active == [liveID])
    }
}

@Suite struct CodexScannerTests {
    private func scan(_ home: FakeHome, openFiles: Set<String> = []) -> [Session] {
        CodexSessionScanner(
            codexHome: home.url.appendingPathComponent(".codex"),
            namesOfOpenFiles: { _ in openFiles }
        ).scan()
    }

    private func rollout(id: String = codexID, cwd: String = "/work/api") -> [String] {
        [
            #"{"type":"session_meta","payload":{"id":"\#(id)","cwd":"\#(cwd)"}}"#,
            #"{"type":"response_item","payload":{"type":"message","role":"developer","content":[{"type":"input_text","text":"system"}]}}"#,
            #"{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"<environment_context>x</environment_context>"}]}}"#,
            #"{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"add caching"}]}}"#,
        ]
    }

    @Test func readsMetadataAndSkipsInjectedContext() throws {
        let home = FakeHome()
        defer { home.remove() }
        try home.write(rollout(), to: ".codex/sessions/2026/11/04/rollout-2026-11-04T08-00-00-\(codexID).jsonl")

        let session = try #require(scan(home).first)
        #expect(session.id == codexID)
        #expect(session.source == .codex)
        #expect(session.projectPath == "/work/api")
        #expect(session.firstMessage == "add caching")
    }

    @Test func usesLatestNameFromIndex() throws {
        let home = FakeHome()
        defer { home.remove() }
        try home.write(rollout(), to: ".codex/sessions/2026/11/04/rollout-2026-11-04T08-00-00-\(codexID).jsonl")
        try home.write(
            [
                #"{"id":"\#(codexID)","thread_name":"generated"}"#,
                #"{"id":"other","thread_name":"unrelated"}"#,
                #"{"id":"\#(codexID)","thread_name":"renamed"}"#,
            ],
            to: ".codex/session_index.jsonl"
        )

        #expect(scan(home).first?.name == "renamed")
    }

    @Test func includesArchivedSessions() throws {
        let home = FakeHome()
        defer { home.remove() }
        try home.write(rollout(), to: ".codex/archived_sessions/rollout-2026-11-04T08-00-00-\(codexID).jsonl")

        #expect(scan(home).count == 1)
    }

    @Test func fallsBackToFileNameWhenMetadataIsUnreadable() throws {
        let home = FakeHome()
        defer { home.remove() }
        try home.write(["not json"], to: ".codex/sessions/2026/11/04/rollout-2026-11-04T08-00-00-\(codexID).jsonl")

        #expect(scan(home).first?.id == codexID)
    }

    @Test func activeFollowsOpenLockNotLockFileExistence() throws {
        let home = FakeHome()
        defer { home.remove() }
        try home.write(rollout(), to: ".codex/sessions/2026/11/04/rollout-2026-11-04T08-00-00-\(codexID).jsonl")
        try home.write([""], to: ".codex/thread-writer-locks/\(codexID).lock")

        #expect(scan(home).first?.isActive == false)
        #expect(scan(home, openFiles: ["\(codexID).lock"]).first?.isActive == true)
    }
}

@Suite struct SharedScanningTests {
    @Test func openFilesReportsOnlyFilesHeldOpen() throws {
        let home = FakeHome()
        defer { home.remove() }
        try home.write(["x"], to: "open.lock")
        try home.write(["x"], to: "closed.lock")
        let open = home.url.appendingPathComponent("open.lock")
        let closed = home.url.appendingPathComponent("closed.lock")

        let handle = try FileHandle(forReadingFrom: open)
        defer { try? handle.close() }

        #expect(OpenFiles.names(of: [open, closed]) == ["open.lock"])
    }

    @Test func dropsLineCutOffByByteLimit() throws {
        let home = FakeHome()
        defer { home.remove() }
        try home.write([#"{"n":1}"#, #"{"n":2}"#], to: "head.jsonl")

        let records = JSONLSample.head(of: home.url.appendingPathComponent("head.jsonl"), byteLimit: 10)
        #expect(records.count == 1)
    }

    @Test func tailDropsLineCutOffByByteLimit() throws {
        let home = FakeHome()
        defer { home.remove() }
        try home.write([#"{"n":1}"#, #"{"n":2}"#], to: "tail.jsonl")

        let records = JSONLSample.tail(of: home.url.appendingPathComponent("tail.jsonl"), byteLimit: 10)
        #expect(records.map { $0["n"] as? Int } == [2])
    }

    @Test func titlePrefersNameOverFirstMessage() {
        func session(name: String?, message: String?) -> Session {
            Session(
                id: "id", source: .codex, name: name, projectPath: nil, firstMessage: message,
                updatedAt: Date(), size: 0, fileURL: URL(fileURLWithPath: "/id"), isActive: false
            )
        }

        #expect(session(name: "named", message: "typed").title == "named")
        #expect(session(name: nil, message: "typed").title == "typed")
        #expect(session(name: nil, message: nil).title == nil)
    }

    @Test func missingDirectoriesYieldNoSessions() {
        let home = FakeHome()
        #expect(SessionScanner(homeDirectory: home.url).scan().isEmpty)
    }

    @Test func groupsByProjectNewestFirst() {
        func session(_ id: String, _ path: String?, _ age: TimeInterval) -> Session {
            Session(
                id: id, source: .codex, projectPath: path, firstMessage: nil,
                updatedAt: Date(timeIntervalSinceNow: -age), size: 10,
                fileURL: URL(fileURLWithPath: "/\(id)"), isActive: false
            )
        }

        let groups = SessionGroup.grouping([
            session("old", "/a", 300), session("mid", "/b", 200), session("new", "/a", 100),
        ])

        #expect(groups.map(\.projectPath) == ["/a", "/b"])
        #expect(groups[0].sessions.map(\.id) == ["new", "old"])
        #expect(groups[0].totalSize == 20)
    }
}
