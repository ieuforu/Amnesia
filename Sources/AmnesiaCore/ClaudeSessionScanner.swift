import Darwin
import Foundation

/// Finds Claude Code CLI sessions in `~/.claude`.
///
/// Each session is `projects/<encoded-path>/<uuid>.jsonl`. The working
/// directory comes from the transcript, because the encoded directory name
/// can't be reversed: `/` and `-` both become `-`.
struct ClaudeSessionScanner {
    let claudeHome: URL

    func scan() -> [Session] {
        let activeIDs = activeSessionIDs()
        let projectsRoot = claudeHome.appendingPathComponent("projects")

        return contents(of: projectsRoot).flatMap { projectDirectory in
            contents(of: projectDirectory).compactMap { file in
                session(at: file, activeIDs: activeIDs)
            }
        }
    }

    private func session(at url: URL, activeIDs: Set<String>) -> Session? {
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
            firstMessage: records.lazy.compactMap(Self.firstMessage).first,
            updatedAt: file.updatedAt,
            size: file.size,
            fileURL: url,
            isActive: activeIDs.contains(id)
        )
    }

    /// Renames are appended to the transcript, so the latest one is near the end.
    private static func customTitle(in url: URL) -> String? {
        JSONLSample.tail(of: url)
            .last { $0["type"] as? String == "custom-title" }
            .flatMap { $0["customTitle"] as? String }
            .flatMap { $0.isEmpty ? nil : $0 }
    }

    private static func firstMessage(in record: [String: Any]) -> String? {
        guard
            record["type"] as? String == "user",
            record["isMeta"] as? Bool != true,
            record["isSidechain"] as? Bool != true,
            let message = record["message"] as? [String: Any]
        else { return nil }

        switch message["content"] {
        case let text as String:
            return MessageText.preview(text)
        case let blocks as [[String: Any]]:
            return MessageText.preview(MessageText.joinedText(from: blocks, blockType: "text"))
        default:
            return nil
        }
    }

    /// Running sessions register `sessions/<pid>.json`, which outlives a crash,
    /// so the pid has to be checked too.
    func activeSessionIDs() -> Set<String> {
        let registrations = contents(of: claudeHome.appendingPathComponent("sessions"))
            .filter { $0.pathExtension == "json" }

        return Set(
            registrations.compactMap { url -> String? in
                guard
                    let data = try? Data(contentsOf: url),
                    let object = try? JSONSerialization.jsonObject(with: data),
                    let registration = object as? [String: Any],
                    let id = registration["sessionId"] as? String,
                    let pid = registration["pid"] as? Int32,
                    Self.isRunning(pid)
                else { return nil }
                return id
            })
    }

    private static func isRunning(_ pid: Int32) -> Bool {
        // EPERM means the process exists but belongs to another user.
        kill(pid, 0) == 0 || errno == EPERM
    }

    private func contents(of directory: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        )) ?? []
    }
}
