import Foundation

/// Reads records from the ends of a JSONL file without loading all of it.
///
/// Transcripts can reach tens of megabytes. Metadata and the first message sit
/// at the start, and the latest session name sits near the end.
enum JSONLSample {
    static let defaultByteLimit = 256 * 1024

    static func head(of url: URL, byteLimit: Int = defaultByteLimit) -> [[String: Any]] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }

        guard let data = try? handle.read(upToCount: byteLimit), !data.isEmpty else { return [] }

        var lines = data.split(separator: 0x0A)
        if data.count == byteLimit, data.last != 0x0A {
            // The limit landed mid-line, so the last line is incomplete.
            lines.removeLast()
        }
        return records(from: lines)
    }

    static func tail(of url: URL, byteLimit: Int = defaultByteLimit) -> [[String: Any]] {
        guard
            let handle = try? FileHandle(forReadingFrom: url),
            let size = try? handle.seekToEnd()
        else { return [] }
        defer { try? handle.close() }

        let start = size > UInt64(byteLimit) ? size - UInt64(byteLimit) : 0
        guard
            (try? handle.seek(toOffset: start)) != nil,
            let data = try? handle.readToEnd()
        else { return [] }

        var lines = data.split(separator: 0x0A)
        if start > 0, !lines.isEmpty {
            // Reading began mid-line, so the first line is incomplete.
            lines.removeFirst()
        }
        return records(from: lines)
    }

    private static func records(from lines: [Data]) -> [[String: Any]] {
        lines.compactMap { line in
            (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any]
        }
    }
}
