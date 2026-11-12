import Foundation

/// Finds Codex CLI sessions in `~/.codex`.
///
/// Each session is a `rollout-*.jsonl` file under the session roots.
struct CodexSessionScanner {
    let paths: AgentPaths
    let activity: SessionActivity.Snapshot

    func scan() -> [Session] {
        let names = sessionNames()
        return paths.codexRollouts().compactMap { session(at: $0, names: names) }
    }

    private func session(at url: URL, names: [String: String]) -> Session? {
        guard let file = SessionFile(url: url) else { return nil }

        let records = JSONLSample.head(of: url)
        let metadata = records.lazy.compactMap(Self.metadata).first
        guard
            let id = metadata?["id"] as? String
                ?? AgentPaths.codexSessionID(inFileName: url.lastPathComponent)
        else { return nil }
        let tail = file.size < Int64(JSONLSample.defaultByteLimit) ? records : JSONLSample.tail(of: url)

        return Session(
            id: id,
            source: .codex,
            name: names[id],
            projectPath: metadata?["cwd"] as? String,
            firstMessage: MessageText.firstTyped(inHead: records, of: url, source: .codex),
            latestUserMessage: MessageText.latestTyped(in: tail, source: .codex),
            updatedAt: file.updatedAt,
            size: file.size,
            fileURL: url,
            isActive: activity.isInUse(id: id, lastWrite: file.updatedAt)
        )
    }

    /// `session_index.jsonl` gains a line per rename, so later lines win.
    private func sessionNames() -> [String: String] {
        guard let data = try? Data(contentsOf: paths.codexSessionIndex) else { return [:] }

        var names: [String: String] = [:]
        for line in data.split(separator: 0x0A) {
            guard
                let object = try? JSONSerialization.jsonObject(with: Data(line)),
                let entry = object as? [String: Any],
                let id = entry["id"] as? String,
                let name = entry["thread_name"] as? String,
                !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                !MessageText.isCodexPreambleTitle(name)
            else { continue }
            names[id] = name
        }
        return names
    }

    private static func metadata(in record: [String: Any]) -> [String: Any]? {
        guard record["type"] as? String == "session_meta" else { return nil }
        return record["payload"] as? [String: Any]
    }
}
