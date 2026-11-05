import Foundation

/// Finds Codex CLI sessions in `~/.codex`.
///
/// Live sessions are stored as `sessions/YYYY/MM/DD/rollout-*.jsonl` and
/// archived ones under `archived_sessions/`.
struct CodexSessionScanner {
    let codexHome: URL
    var namesOfOpenFiles: ([URL]) -> Set<String> = OpenFiles.names

    func scan() -> [Session] {
        let openLocks = openLocks()

        return ["sessions", "archived_sessions"]
            .flatMap { rollouts(in: codexHome.appendingPathComponent($0)) }
            .compactMap { session(at: $0, openLocks: openLocks) }
    }

    /// The lock files of sessions a running Codex process owns.
    func openLocks() -> Set<String> {
        namesOfOpenFiles(writerLocks())
    }

    private func session(at url: URL, openLocks: Set<String>) -> Session? {
        guard let file = SessionFile(url: url) else { return nil }

        let records = JSONLHead.records(in: url)
        let metadata = records.lazy.compactMap(Self.metadata).first
        guard let id = metadata?["id"] as? String ?? Self.id(fromFileName: url) else { return nil }

        return Session(
            id: id,
            source: .codex,
            projectPath: metadata?["cwd"] as? String,
            firstMessage: records.lazy.compactMap(Self.firstMessage).first,
            updatedAt: file.updatedAt,
            size: file.size,
            fileURL: url,
            isActive: openLocks.contains("\(id).lock")
        )
    }

    private static func metadata(in record: [String: Any]) -> [String: Any]? {
        guard record["type"] as? String == "session_meta" else { return nil }
        return record["payload"] as? [String: Any]
    }

    private static func firstMessage(in record: [String: Any]) -> String? {
        guard
            record["type"] as? String == "response_item",
            let payload = record["payload"] as? [String: Any],
            payload["type"] as? String == "message",
            payload["role"] as? String == "user",
            let blocks = payload["content"] as? [[String: Any]]
        else { return nil }

        return MessageText.preview(MessageText.joinedText(from: blocks, blockType: "input_text"))
    }

    /// `rollout-<timestamp>-<uuid>.jsonl`, used when the metadata line is unreadable.
    private static func id(fromFileName url: URL) -> String? {
        let candidate = String(url.deletingPathExtension().lastPathComponent.suffix(36))
        return UUID(uuidString: candidate) == nil ? nil : candidate
    }

    private func rollouts(in directory: URL) -> [URL] {
        guard
            let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
            )
        else { return [] }

        return enumerator.compactMap { $0 as? URL }.filter {
            $0.pathExtension == "jsonl" && $0.lastPathComponent.hasPrefix("rollout-")
        }
    }

    private func writerLocks() -> [URL] {
        let directory = codexHome.appendingPathComponent("thread-writer-locks")
        let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        )
        return (files ?? []).filter { $0.pathExtension == "lock" }
    }
}
