import Foundation

/// Reads records from the start of a JSONL file without loading all of it.
///
/// Transcripts can reach tens of megabytes, while the metadata and first
/// message sit near the top.
enum JSONLHead {
    static let defaultByteLimit = 256 * 1024

    static func records(in url: URL, byteLimit: Int = defaultByteLimit) -> [[String: Any]] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }

        guard let data = try? handle.read(upToCount: byteLimit), !data.isEmpty else { return [] }

        var lines = data.split(separator: 0x0A)
        if data.count == byteLimit, data.last != 0x0A {
            // The limit landed mid-line, so the last line is incomplete.
            lines.removeLast()
        }

        return lines.compactMap { line in
            (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any]
        }
    }
}
