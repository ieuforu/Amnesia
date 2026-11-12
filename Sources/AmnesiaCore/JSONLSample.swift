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
        guard byteLimit > 0, let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }

        guard let size = try? handle.seekToEnd() else { return [] }
        let start = size > UInt64(byteLimit) ? size - UInt64(byteLimit) : 0
        // Include the byte before the limit so a line starting at it survives.
        let offset = start > 0 ? start - 1 : 0
        guard
            (try? handle.seek(toOffset: offset)) != nil,
            let data = try? handle.read(upToCount: byteLimit + Int(start - offset)),
            !data.isEmpty
        else { return [] }

        let lines = data.split(separator: 0x0A, omittingEmptySubsequences: false)
        return records(from: start > 0 ? Array(lines.dropFirst()) : lines)
    }

    private static func records(from lines: [Data]) -> [[String: Any]] {
        lines.compactMap { line in
            (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any]
        }
    }
}
