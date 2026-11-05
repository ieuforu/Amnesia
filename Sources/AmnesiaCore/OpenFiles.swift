import Foundation

/// Asks `lsof` which files a process has open.
///
/// Codex keeps a lock file for each running session and leaves it behind when
/// it exits, so the file's existence proves nothing. Taking the lock to test
/// it could collide with a starting session, and `lsof` only observes.
enum OpenFiles {
    /// Returns the file names of the given URLs that are currently open.
    static func names(of urls: [URL]) -> Set<String> {
        guard !urls.isEmpty else { return [] }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-Fn", "--"] + urls.map(\.path)

        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        guard (try? process.run()) != nil else { return [] }

        // Read before waiting, or a full pipe would block lsof forever.
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let lines = String(decoding: data, as: UTF8.self).split(separator: "\n")
        return Set(
            lines
                .filter { $0.hasPrefix("n") }
                .map { URL(fileURLWithPath: String($0.dropFirst())).lastPathComponent }
        )
    }
}
