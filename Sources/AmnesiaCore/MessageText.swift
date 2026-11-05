import Foundation

enum MessageText {
    private static let maxLength = 200
    private static let fallbackByteLimit = SessionReader.byteLimit / 2

    /// Returns a single-line preview of text the user typed, or nil for
    /// injected content, which agents wrap in tags such as
    /// `<environment_context>`.
    static func preview(_ text: String) -> String? {
        let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !collapsed.isEmpty, !isInjected(collapsed) else { return nil }
        return String(collapsed.prefix(maxLength))
    }

    static func isInjected(_ text: String) -> Bool {
        text.drop(while: \.isWhitespace).hasPrefix("<")
    }

    /// The first thing the user typed, as a preview.
    static func firstTyped(in records: [[String: Any]], source: SessionSource) -> String? {
        records.lazy
            .compactMap { TranscriptFormat.turn(in: $0, source: source) }
            .filter { $0.role == .user }
            .compactMap { preview($0.text) }
            .first
    }

    /// Looks at the end of the file only when the start has nothing typed,
    /// which happens when tool output fills the start of a transcript.
    static func firstTyped(inHead records: [[String: Any]], of url: URL, source: SessionSource) -> String? {
        firstTyped(in: records, source: source)
            ?? firstTyped(in: JSONLSample.tail(of: url, byteLimit: fallbackByteLimit), source: source)
    }

    /// Joins the text blocks of a message's `content` array.
    static func joinedText(from blocks: [[String: Any]], blockType: String) -> String {
        blocks
            .filter { $0["type"] as? String == blockType }
            .compactMap { $0["text"] as? String }
            .joined(separator: " ")
    }
}
