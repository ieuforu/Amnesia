import Foundation

enum MessageText {
    private static let maxLength = 200

    /// Returns a single-line preview of text the user typed, or nil for
    /// injected content, which agents wrap in tags such as
    /// `<environment_context>`.
    static func preview(_ text: String) -> String? {
        let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !collapsed.isEmpty, !collapsed.hasPrefix("<") else { return nil }
        return String(collapsed.prefix(maxLength))
    }

    /// Joins the text blocks of a message's `content` array.
    static func joinedText(from blocks: [[String: Any]], blockType: String) -> String {
        blocks
            .filter { $0["type"] as? String == blockType }
            .compactMap { $0["text"] as? String }
            .joined(separator: " ")
    }
}
