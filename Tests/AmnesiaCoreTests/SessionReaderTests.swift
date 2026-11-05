import Foundation
import Testing

@testable import AmnesiaCore

private func makeHome() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("amnesia-reader-\(UUID().uuidString)")
}

private func write(_ text: String, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try text.write(to: url, atomically: true, encoding: .utf8)
}

private func session(_ source: SessionSource, id: String, file: URL) -> Session {
    Session(
        id: id,
        source: source,
        projectPath: "/work/app",
        firstMessage: nil,
        updatedAt: Date(),
        size: Int64((try? Data(contentsOf: file).count) ?? 0),
        fileURL: file,
        isActive: false
    )
}

@Suite struct SessionReaderTests {
    private let id = "aaaaaaaa-0000-4000-8000-000000000001"

    @Test func claudePreviewKeepsOnlyConversationTurns() throws {
        let home = makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let file = home.appendingPathComponent(".claude/projects/-work-app/\(id).jsonl")
        try write(
            [
                #"{"type":"mode"}"#,
                #"{"type":"user","isMeta":true,"message":{"content":"injected"}}"#,
                #"{"type":"user","message":{"content":"<command-name>/clear</command-name>"}}"#,
                #"{"type":"user","message":{"content":"fix the bug"}}"#,
                #"{"type":"assistant","message":{"content":[{"type":"thinking","thinking":"hmm"},{"type":"text","text":"On it."}]}}"#,
                #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash"}]}}"#,
                #"{"type":"user","message":{"content":[{"type":"tool_result","content":"output"}]}}"#,
                #"{"type":"assistant","isSidechain":true,"message":{"content":[{"type":"text","text":"subagent"}]}}"#,
                #"{"type":"assistant","message":{"content":[{"type":"text","text":"Done."}]}}"#,
            ].joined(separator: "\n"),
            to: file
        )

        let detail = SessionReader(homeDirectory: home).detail(for: session(.claudeCode, id: id, file: file))

        #expect(detail.messages.map(\.text) == ["fix the bug", "On it.", "Done."])
        #expect(detail.messages.map(\.role) == [.user, .agent, .agent])
        #expect(detail.omittedAfter == nil)
    }

    @Test func codexPreviewSkipsDeveloperAndToolRecords() throws {
        let home = makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let file = home.appendingPathComponent(".codex/sessions/2026/11/05/rollout-x-\(id).jsonl")
        try write(
            [
                #"{"type":"response_item","payload":{"type":"message","role":"developer","content":[{"type":"input_text","text":"rules"}]}}"#,
                #"{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"<environment_context>x</environment_context>"}]}}"#,
                #"{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"add tests"}]}}"#,
                #"{"type":"response_item","payload":{"type":"reasoning","summary":[]}}"#,
                #"{"type":"response_item","payload":{"type":"function_call","name":"shell"}}"#,
                #"{"type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Added."}]}}"#,
            ].joined(separator: "\n"),
            to: file
        )

        let detail = SessionReader(homeDirectory: home).detail(for: session(.codex, id: id, file: file))

        #expect(detail.messages.map(\.text) == ["add tests", "Added."])
        #expect(detail.messages.map(\.role) == [.user, .agent])
    }

    @Test func longConversationsKeepBothEndsAndMarkTheGap() throws {
        let home = makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let file = home.appendingPathComponent(".claude/projects/-work-app/\(id).jsonl")
        let lines = (0..<(SessionReader.messageLimit + 5)).map {
            #"{"type":"user","message":{"content":"message \#($0)"}}"#
        }
        try write(lines.joined(separator: "\n"), to: file)

        let detail = SessionReader(homeDirectory: home).detail(for: session(.claudeCode, id: id, file: file))

        #expect(detail.messages.count == SessionReader.messageLimit)
        #expect(detail.messages.first?.text == "message 0")
        #expect(detail.messages.last?.text == "message \(SessionReader.messageLimit + 4)")
        #expect(detail.omittedAfter == SessionReader.messageLimit / 2)
    }

    @Test func messagesPastTheStartOfALargeFileAreStillFound() throws {
        let home = makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let file = home.appendingPathComponent(".claude/projects/-work-app/\(id).jsonl")
        let padding = String(repeating: "x", count: SessionReader.byteLimit)
        try write(
            [
                #"{"type":"assistant","message":{"content":[{"type":"text","text":"Early."}]}}"#,
                #"{"type":"assistant","message":{"content":[{"type":"tool_use","input":"\#(padding)"}]}}"#,
                #"{"type":"user","message":{"content":"typed late"}}"#,
            ].joined(separator: "\n"),
            to: file
        )

        let detail = SessionReader(homeDirectory: home).detail(for: session(.claudeCode, id: id, file: file))

        #expect(detail.messages.map(\.text) == ["Early.", "typed late"])
        #expect(detail.omittedAfter == 1)
    }

    @Test func listsClaudeFilesWithSizesAndShortPaths() throws {
        let home = makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let file = home.appendingPathComponent(".claude/projects/-work-app/\(id).jsonl")
        try write("{}", to: file)
        try write("12345", to: home.appendingPathComponent(".claude/file-history/\(id)/a.txt"))

        let files = SessionReader(homeDirectory: home).detail(for: session(.claudeCode, id: id, file: file)).files

        #expect(files.map(\.label) == ["Transcript", "File history"])
        #expect(files[0].path == "~/.claude/projects/-work-app/\(id).jsonl")
        #expect(files[1].size == 5)
    }

    @Test func listsCodexShellSnapshots() throws {
        let home = makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let file = home.appendingPathComponent(".codex/sessions/2026/11/05/rollout-x-\(id).jsonl")
        try write("{}", to: file)
        try write("x", to: home.appendingPathComponent(".codex/shell_snapshots/\(id).123.sh"))
        try write("x", to: home.appendingPathComponent(".codex/shell_snapshots/other.123.sh"))

        let files = SessionReader(homeDirectory: home).detail(for: session(.codex, id: id, file: file)).files

        #expect(files.map(\.label) == ["Transcript", "Shell snapshot"])
    }
}
