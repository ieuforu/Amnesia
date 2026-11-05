import Foundation

/// Finds Claude Code CLI sessions in `~/.claude`.
///
/// Each session is `projects/<encoded-path>/<uuid>.jsonl`. The working
/// directory comes from the transcript, because the encoded directory name
/// can't be reversed: `/` and `-` both become `-`.
struct ClaudeSessionScanner {
    let paths: AgentPaths
    let activity: SessionActivity.Snapshot

    func scan() -> [Session] {
        contents(of: paths.claudeProjects).flatMap { projectDirectory in
            contents(of: projectDirectory).compactMap(session(at:))
        }
    }

    private func session(at url: URL) -> Session? {
        let id = url.deletingPathExtension().lastPathComponent
        guard
            url.pathExtension == "jsonl",
            UUID(uuidString: id) != nil,
            let file = SessionFile(url: url)
        else { return nil }

        let records = JSONLSample.head(of: url)

        return Session(
            id: id,
            source: .claudeCode,
            name: Self.customTitle(in: url),
            projectPath: records.lazy.compactMap { $0["cwd"] as? String }.first,
            firstMessage: MessageText.firstTyped(inHead: records, of: url, source: .claudeCode),
            updatedAt: file.updatedAt,
            size: file.size,
            fileURL: url,
            isActive: activity.isInUse(id: id, lastWrite: file.updatedAt)
        )
    }

    /// Renames are appended to the transcript, so the latest one is near the end.
    private static func customTitle(in url: URL) -> String? {
        JSONLSample.tail(of: url)
            .last { $0["type"] as? String == "custom-title" }
            .flatMap { $0["customTitle"] as? String }
            .flatMap { $0.isEmpty ? nil : $0 }
    }

    private func contents(of directory: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        )) ?? []
    }
}
