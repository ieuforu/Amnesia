import Foundation
import SQLite3

/// Reads Codex's thread records, which outlive a transcript removed by hand.
enum CodexThreadStore {
    struct OrphanedThread {
        let id: String
        let updatedAt: Date
    }

    /// Finds threads whose transcript is gone. Any failure, such as a changed
    /// schema, yields nothing, so unknown data is never treated as a leftover.
    static func orphanedThreads(at databaseURL: URL) -> [OrphanedThread] {
        let path = databaseURL.path
        guard FileManager.default.fileExists(atPath: path) else { return [] }

        var database: OpaquePointer?
        defer { sqlite3_close(database) }
        guard sqlite3_open_v2(path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return [] }

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        let query = "SELECT id, rollout_path, updated_at FROM threads"
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else { return [] }

        var orphans: [OrphanedThread] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard
                let id = sqlite3_column_text(statement, 0),
                let rolloutPath = sqlite3_column_text(statement, 1)
            else { continue }

            if !FileManager.default.fileExists(atPath: String(cString: rolloutPath)) {
                orphans.append(
                    OrphanedThread(
                        id: String(cString: id),
                        updatedAt: Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(statement, 2)))
                    )
                )
            }
        }
        return orphans
    }
}
