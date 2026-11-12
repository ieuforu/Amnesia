import AmnesiaCore
import AppKit

struct SessionResume: Sendable {
    private let directory: String
    private let id: UUID

    init?(_ session: Session) {
        guard session.source == .claudeCode,
              let id = UUID(uuidString: session.id),
              let directory = session.projectPath,
              directory.hasPrefix("/")
        else { return nil }
        self.directory = directory
        self.id = id
    }

    var command: String {
        let quotedDirectory = "'" + directory.replacingOccurrences(of: "'", with: "'\\''") + "'"
        return "cd -- \(quotedDirectory) && \(resumeCommand)"
    }

    private var resumeCommand: String {
        "claude --resume \(id.uuidString.lowercased())"
    }

    @MainActor
    func openInGhostty() async throws {
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.mitchellh.ghostty") != nil else {
            throw ResumeError.ghosttyUnavailable
        }

        try await Task.detached(priority: .userInitiated) {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: directory, isDirectory: &isDirectory), isDirectory.boolValue else {
                throw ResumeError.directoryUnavailable
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", Self.ghosttyScript, directory, resumeCommand]
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw ResumeError.automationFailed }
        }.value
    }

    private static let ghosttyScript = """
        on run argv
            set sessionDirectory to item 1 of argv
            set resumeInput to (item 2 of argv) & linefeed
            tell application id "com.mitchellh.ghostty"
                set cfg to new surface configuration
                set initial working directory of cfg to sessionDirectory
                set initial input of cfg to resumeInput
                if (count of windows) is 0 then
                    new window with configuration cfg
                else
                    new tab in (window 1) with configuration cfg
                end if
                activate
            end tell
        end run
        """
}

private enum ResumeError: LocalizedError {
    case ghosttyUnavailable, directoryUnavailable, automationFailed

    var errorDescription: String? {
        switch self {
        case .ghosttyUnavailable: "Ghostty is not installed. You can copy the command and run it in your terminal."
        case .directoryUnavailable: "The original working directory is no longer available."
        case .automationFailed: "Amnesia couldn't open a Ghostty tab. You can copy the resume command instead."
        }
    }
}
