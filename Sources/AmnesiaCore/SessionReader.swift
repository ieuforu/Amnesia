import Foundation

/// Reads what a session holds for the main window. It never changes anything.
public struct SessionReader: Sendable {
    /// Transcripts reach hundreds of megabytes, so a preview reads both ends.
    /// Tool output can fill most of a file, so the start alone may hold nothing
    /// the user typed.
    static let byteLimit = 8 * 1024 * 1024
    static let messageLimit = 100
    static let messageLengthLimit = 4000

    private let paths: AgentPaths

    public init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        paths = AgentPaths(home: homeDirectory)
    }

    public func detail(for session: Session) -> SessionDetail {
        let (first, last) = turns(in: session)
        let all = first + last

        // Keeps both ends when there's more than fits, as the file read does.
        let shown: [TranscriptFormat.Turn]
        var omittedAfter = !first.isEmpty && !last.isEmpty ? first.count : nil
        if all.count > Self.messageLimit {
            shown = all.prefix(Self.messageLimit / 2) + all.suffix(Self.messageLimit / 2)
            omittedAfter = Self.messageLimit / 2
        } else {
            shown = all
        }

        let messages = shown.enumerated().map { index, turn in
            TranscriptMessage(id: index, role: turn.role, text: Self.shortened(turn.text))
        }
        return SessionDetail(messages: messages, omittedAfter: omittedAfter, files: files(of: session))
    }

    /// The conversation from the start and end of the file. `last` is empty
    /// when the whole file fits in `first`.
    private func turns(in session: Session) -> (first: [TranscriptFormat.Turn], last: [TranscriptFormat.Turn]) {
        guard session.size > Int64(Self.byteLimit) else {
            return (conversation(in: JSONLSample.head(of: session.fileURL, byteLimit: Self.byteLimit), session), [])
        }
        let half = Self.byteLimit / 2
        return (
            conversation(in: JSONLSample.head(of: session.fileURL, byteLimit: half), session),
            conversation(in: JSONLSample.tail(of: session.fileURL, byteLimit: half), session)
        )
    }

    private func conversation(in records: [[String: Any]], _ session: Session) -> [TranscriptFormat.Turn] {
        var turns: [TranscriptFormat.Turn] = []
        for record in records {
            guard let turn = TranscriptFormat.turn(in: record, source: session.source) else { continue }
            let text = turn.text.trimmingCharacters(in: .whitespacesAndNewlines)
            // Agents can record one reply more than once.
            guard !text.isEmpty, turns.last?.text != text else { continue }
            turns.append((turn.role, text))
        }
        return turns
    }

    private static func shortened(_ text: String) -> String {
        text.count > messageLengthLimit ? text.prefix(messageLengthLimit) + "…" : text
    }

    private func files(of session: Session) -> [StoredFile] {
        let transcript = StoredFile(
            label: "Transcript",
            path: displayPath(session.fileURL),
            size: Self.size(of: session.fileURL)
        )

        let others: [StoredFile]
        switch session.source {
        case .claudeCode:
            others = paths.claudeSidecars(ofTranscript: session.fileURL, id: session.id)
                .filter { FileManager.default.fileExists(atPath: $0.path) }
                .map { stored($0, label: Self.claudeSidecarLabel($0)) }
        case .codex:
            others = paths.codexShellSnapshots(forSession: session.id)
                .map { stored($0, label: "Shell snapshot") }
        }
        return [transcript] + others
    }

    private func stored(_ url: URL, label: String) -> StoredFile {
        StoredFile(label: label, path: displayPath(url), size: Self.size(of: url))
    }

    private static func claudeSidecarLabel(_ url: URL) -> String {
        switch url.deletingLastPathComponent().lastPathComponent {
        case "file-history": "File history"
        case "session-env": "Session environment"
        default: "Session files"
        }
    }

    private func displayPath(_ url: URL) -> String {
        let home = paths.home.path
        return url.path.hasPrefix(home + "/") ? "~" + url.path.dropFirst(home.count) : url.path
    }

    /// The size of a file, or of everything inside a folder.
    private static func size(of url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .isRegularFileKey]
        guard FileManager.default.fileExists(atPath: url.path) else { return 0 }

        if let size = SessionFile(url: url)?.size { return size }

        let contents = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys))
        return (contents?.compactMap { $0 as? URL } ?? []).reduce(0) { total, file in
            let values = try? file.resourceValues(forKeys: keys)
            return total + Int64(values?.isRegularFile == true ? values?.fileSize ?? 0 : 0)
        }
    }
}
