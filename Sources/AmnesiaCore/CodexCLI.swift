import Foundation

enum CodexCLIError: LocalizedError {
    case notInstalled
    case deleteFailed

    var errorDescription: String? {
        switch self {
        case .notInstalled: "The codex command wasn't found."
        case .deleteFailed: "The codex command couldn't delete it."
        }
    }
}

/// Runs the official Codex CLI, which owns the session databases.
enum CodexCLI {
    private static let timeout: DispatchTimeInterval = .seconds(30)

    /// `paths` is passed through so the command acts on the same folder that
    /// was scanned.
    static func deleteSession(id: String, paths: AgentPaths) throws {
        guard let executable else {
            throw CodexCLIError.notInstalled
        }

        let process = Process()
        process.executableURL = executable
        process.arguments = ["delete", "--force", id]
        process.currentDirectoryURL = paths.home
        process.environment = [
            "HOME": paths.home.path,
            "CODEX_HOME": paths.codexHomeDirectory.path,
            "PATH": "/usr/bin:/bin",
        ]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        try process.run()

        guard finished.wait(timeout: .now() + timeout) == .success else {
            process.terminate()
            throw CodexCLIError.deleteFailed
        }
        guard process.terminationStatus == 0 else { throw CodexCLIError.deleteFailed }
    }

    /// Apps opened from Finder don't inherit the shell's PATH, so look in the
    /// usual install locations.
    private static var executable: URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.codex/packages/standalone/current/bin/codex",
            "\(home)/.local/bin/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
        ]
        return candidates
            .first { FileManager.default.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }
}
