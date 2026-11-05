import Foundation

/// Rewrites an agent's prompt history, which holds one JSON entry per line.
enum HistoryFile {
    private static let maxAttempts = 3

    /// Removes entries whose `key` is one of `values`, leaving every other line
    /// exactly as it was, including lines that aren't valid JSON.
    ///
    /// Running agents append to these files without any shared lock, so the
    /// file is re-checked before replacing it and the rewrite is retried if it
    /// grew. That narrows the race but can't fully close it.
    static func removeEntries(at url: URL, forKey key: String, values: Set<String>) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        for _ in 0..<maxAttempts {
            let original = try Data(contentsOf: url)
            let lines = original.split(separator: 0x0A, omittingEmptySubsequences: false)
            let kept = lines.filter { !matches($0, key: key, values: values) }
            guard kept.count != lines.count else { return }

            var rewritten = Data()
            for (index, line) in kept.enumerated() {
                if index > 0 { rewritten.append(0x0A) }
                rewritten.append(line)
            }

            guard try Data(contentsOf: url) == original else { continue }

            // Prompts are private, so keep the file's restrictive permissions.
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            try rewritten.write(to: url, options: .atomic)
            if let permissions = attributes[.posixPermissions] {
                try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
            }
            return
        }

        throw CocoaError(.fileWriteUnknown)
    }

    private static func matches(_ line: Data, key: String, values: Set<String>) -> Bool {
        guard
            let object = try? JSONSerialization.jsonObject(with: Data(line)),
            let entry = object as? [String: Any],
            let value = entry[key] as? String
        else { return false }
        return values.contains(value)
    }
}
