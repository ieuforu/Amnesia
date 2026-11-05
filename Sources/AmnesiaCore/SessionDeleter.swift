import Foundation

public enum DeletionOutcome: Equatable, Sendable {
    case deleted
    /// The session started running again after it was selected.
    case skippedInUse
    case failed(String)
}

public struct DeletionResult: Sendable {
    public let session: Session
    public let outcome: DeletionOutcome
}

/// Deletes sessions and the records that belong to them.
///
/// Transcripts go to the Trash so their content can be recovered. Everything
/// else is removed for good. Each session is re-checked first, because it may
/// have started running since the list was shown.
public struct SessionDeleter: Sendable {
    private let homeDirectory: URL
    private let moveToTrash: @Sendable (URL) throws -> Void
    private let deleteCodexSession: @Sendable (String, URL) throws -> Void
    private let namesOfOpenFiles: @Sendable ([URL]) -> Set<String>

    private var claudeHome: URL { homeDirectory.appendingPathComponent(".claude") }
    private var codexHome: URL { homeDirectory.appendingPathComponent(".codex") }

    public init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.init(
            homeDirectory: homeDirectory,
            moveToTrash: { url in
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            },
            deleteCodexSession: CodexCLI.deleteSession,
            namesOfOpenFiles: OpenFiles.names
        )
    }

    init(
        homeDirectory: URL,
        moveToTrash: @escaping @Sendable (URL) throws -> Void,
        deleteCodexSession: @escaping @Sendable (String, URL) throws -> Void,
        namesOfOpenFiles: @escaping @Sendable ([URL]) -> Set<String>
    ) {
        self.homeDirectory = homeDirectory
        self.moveToTrash = moveToTrash
        self.deleteCodexSession = deleteCodexSession
        self.namesOfOpenFiles = namesOfOpenFiles
    }

    public func delete(_ sessions: [Session]) -> [DeletionResult] {
        sessions.map { DeletionResult(session: $0, outcome: delete($0)) }
    }

    private func delete(_ session: Session) -> DeletionOutcome {
        guard isManaged(session) else {
            return .failed("Its file is outside the expected folder.")
        }
        guard !isInUse(session) else { return .skippedInUse }

        do {
            switch session.source {
            case .claudeCode: try deleteClaudeSession(session)
            case .codex: try deleteCodexSession(session)
            }
            return .deleted
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Refuses anything that isn't a session file in the agent's own folders,
    /// so a bad record can never point a delete somewhere else.
    private func isManaged(_ session: Session) -> Bool {
        guard UUID(uuidString: session.id) != nil, session.fileURL.pathExtension == "jsonl" else {
            return false
        }
        let file = session.fileURL.resolvingSymlinksInPath()

        switch session.source {
        case .claudeCode:
            let projects = claudeHome.appendingPathComponent("projects").resolvingSymlinksInPath()
            return file.lastPathComponent == "\(session.id).jsonl"
                && file.deletingLastPathComponent().deletingLastPathComponent().path == projects.path
        case .codex:
            let roots = ["sessions", "archived_sessions"].map {
                codexHome.appendingPathComponent($0).resolvingSymlinksInPath().path + "/"
            }
            return file.lastPathComponent.hasSuffix("\(session.id).jsonl")
                && roots.contains { file.path.hasPrefix($0) }
        }
    }

    private func isInUse(_ session: Session) -> Bool {
        switch session.source {
        case .claudeCode:
            ClaudeSessionScanner(claudeHome: claudeHome).activeSessionIDs().contains(session.id)
        case .codex:
            CodexSessionScanner(codexHome: codexHome, namesOfOpenFiles: namesOfOpenFiles)
                .openLocks().contains("\(session.id).lock")
        }
    }

    private func deleteClaudeSession(_ session: Session) throws {
        // If this fails nothing has changed yet, so the session stays intact.
        try moveToTrash(session.fileURL)

        let sidecars = [
            session.fileURL.deletingPathExtension(),
            claudeHome.appendingPathComponent("file-history/\(session.id)"),
            claudeHome.appendingPathComponent("session-env/\(session.id)"),
        ]
        for sidecar in sidecars where FileManager.default.fileExists(atPath: sidecar.path) {
            try FileManager.default.removeItem(at: sidecar)
        }

        try HistoryFile.removeEntries(
            at: claudeHome.appendingPathComponent("history.jsonl"),
            forKey: "sessionId",
            value: session.id
        )
    }

    /// `codex delete` is permanent, so a copy of the transcript goes to the
    /// Trash first. If the command then fails, the worst case is a spare copy
    /// in the Trash, and the content can't be lost.
    private func deleteCodexSession(_ session: Session) throws {
        let holdingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Amnesia-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: holdingDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: holdingDirectory) }

        let copy = holdingDirectory.appendingPathComponent(session.fileURL.lastPathComponent)
        try FileManager.default.copyItem(at: session.fileURL, to: copy)

        try moveToTrash(copy)
        try deleteCodexSession(session.id, homeDirectory)

        // `codex delete` leaves these behind, and the history holds typed text.
        let snapshots = codexHome.appendingPathComponent("shell_snapshots")
        let files = (try? FileManager.default.contentsOfDirectory(at: snapshots, includingPropertiesForKeys: nil))
        for file in files ?? [] where file.lastPathComponent.hasPrefix("\(session.id).") {
            try FileManager.default.removeItem(at: file)
        }

        try HistoryFile.removeEntries(
            at: codexHome.appendingPathComponent("history.jsonl"),
            forKey: "session_id",
            value: session.id
        )
    }
}
