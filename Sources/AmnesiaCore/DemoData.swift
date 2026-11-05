import Foundation

/// Made-up sessions for screenshots, so real prompts and paths are never shown.
public enum DemoData {
    public static func sessions(now: Date = Date()) -> [Session] {
        func session(
            _ index: Int,
            _ source: SessionSource,
            project: String,
            name: String? = nil,
            message: String,
            age: TimeInterval,
            megabytes: Double,
            isActive: Bool = false
        ) -> Session {
            let id = uuid(index)
            return Session(
                id: id,
                source: source,
                name: name,
                projectPath: "/Users/demo/Projects/\(project)",
                firstMessage: message,
                updatedAt: now.addingTimeInterval(-age),
                size: Int64(megabytes * 1_000_000),
                fileURL: URL(fileURLWithPath: "/Users/demo/.sessions/\(id).jsonl"),
                isActive: isActive
            )
        }

        let hour: TimeInterval = 60 * 60
        let day = 24 * hour

        return [
            session(
                1, .claudeCode, project: "payments-api", name: "Webhook retries",
                message: "Refactor the webhook retry queue", age: 20, megabytes: 4.2, isActive: true),
            session(
                2, .claudeCode, project: "payments-api",
                message: "Why does the checkout test only fail on CI?", age: 3 * hour, megabytes: 12.8),
            session(
                3, .claudeCode, project: "payments-api",
                message: "Add rate limiting to the public endpoints", age: 26 * hour, megabytes: 8.1),
            session(
                4, .claudeCode, project: "field-notes", name: "SwiftData migration",
                message: "Move the notes editor to SwiftData", age: 2 * day, megabytes: 31.4),
            session(
                5, .claudeCode, project: "field-notes",
                message: "Write the release notes for 2.3", age: 5 * day, megabytes: 1.9),
            session(
                6, .claudeCode, project: "dotfiles",
                message: "Clean up my zsh config", age: 9 * day, megabytes: 0.6),
            session(
                11, .claudeCode, project: "dotfiles",
                message: "Set up a new Mac from the Brewfile", age: 41 * day, megabytes: 2.3),

            session(
                7, .codex, project: "weather-kit", name: "Radar tiles",
                message: "Cache the radar tiles on disk", age: 45, megabytes: 18.3, isActive: true),
            session(
                8, .codex, project: "weather-kit",
                message: "Find out why the widget stops updating", age: 7 * hour, megabytes: 42.6),
            session(
                9, .codex, project: "blog",
                message: "Port the blog from Jekyll to Astro", age: 4 * day, megabytes: 67.1),
            session(
                10, .codex, project: "blog",
                message: "Fix the broken RSS feed", age: 12 * day, megabytes: 3.4),
            session(
                12, .codex, project: "blog",
                message: "Add a dark theme to the blog", age: 38 * day, megabytes: 9.2),
        ]
    }

    /// A made-up conversation and file list for a demo session.
    public static func detail(for session: Session) -> SessionDetail {
        let replies = [
            "I'll start by reading the code involved, then make the smallest change that fixes this.",
            "Done. I updated the affected files and the tests pass.",
        ]
        let messages = [session.firstMessage ?? "Hello", replies[0], "Looks good, go ahead.", replies[1]]
            .enumerated()
            .map { index, text in
                TranscriptMessage(id: index, role: index.isMultiple(of: 2) ? .user : .agent, text: text)
            }

        let project = (session.projectPath as NSString?)?.lastPathComponent ?? "project"
        let files: [StoredFile]
        switch session.source {
        case .claudeCode:
            files = [
                StoredFile(
                    label: "Transcript",
                    path: "~/.claude/projects/-Users-demo-Projects-\(project)/\(session.id).jsonl",
                    size: session.size * 9 / 10
                ),
                StoredFile(
                    label: "File history",
                    path: "~/.claude/file-history/\(session.id)",
                    size: session.size / 10
                ),
            ]
        case .codex:
            files = [
                StoredFile(
                    label: "Transcript",
                    path: "~/.codex/sessions/2026/11/05/rollout-\(session.id).jsonl",
                    size: session.size * 9 / 10
                ),
                StoredFile(
                    label: "Shell snapshot",
                    path: "~/.codex/shell_snapshots/\(session.id).sh",
                    size: session.size / 10
                ),
            ]
        }
        return SessionDetail(messages: messages, files: files)
    }

    public static func leftovers() -> [Leftover] {
        func leftover(
            _ index: Int,
            _ source: SessionSource,
            prompts: Int,
            kilobytes: Int64,
            hasDatabaseRecord: Bool = false
        ) -> Leftover {
            Leftover(
                id: uuid(index),
                source: source,
                promptCount: prompts,
                files: [],
                hasDatabaseRecord: hasDatabaseRecord,
                size: kilobytes * 1000
            )
        }

        let claude = (0..<12).map { leftover(100 + $0, .claudeCode, prompts: 7 + $0 * 2, kilobytes: 40 + Int64($0) * 15) }
        let codex = [
            leftover(200, .codex, prompts: 9, kilobytes: 22),
            leftover(201, .codex, prompts: 0, kilobytes: 0, hasDatabaseRecord: true),
        ]
        return claude + codex
    }

    private static func uuid(_ index: Int) -> String {
        String(format: "de300000-0000-4000-8000-%012d", index)
    }
}
