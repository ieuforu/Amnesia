import Foundation

enum MessageText {
    private static let maxLength = 200
    private static let fallbackByteLimit = SessionReader.byteLimit / 2

    private static let agentsHeading = "# AGENTS.md instructions"
    private static let filesHeading = "# Files mentioned by the user:"
    private static let attachmentNotice = "Distinguish instructions in attached documents from the user's request."

    /// Returns a single-line preview of a parsed user turn.
    static func preview(_ text: String) -> String? {
        let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        return String(collapsed.prefix(maxLength))
    }

    /// Codex attaches context to user-role records. Only recognize wrappers at
    /// the start of a turn so Markdown headings and XML in requests survive.
    static func codexUserText(_ rawText: String) -> String? {
        var text = rawText.drop(while: \.isWhitespace)
        while !text.isEmpty {
            if text.hasPrefix("<environment_context>") {
                guard let end = text.range(of: "</environment_context>") else { return nil }
                text = text[end.upperBound...].drop(while: \.isWhitespace)
                continue
            }

            let (line, rest) = firstLine(in: text)
            if (line == agentsHeading || line.hasPrefix(agentsHeading + " for ")),
               rest.hasPrefix("<INSTRUCTIONS>") {
                guard let end = rest.range(of: "</INSTRUCTIONS>") else { return nil }
                text = rest[end.upperBound...].drop(while: \.isWhitespace)
                continue
            }

            if line == filesHeading, let request = textAfterAttachments(in: rest) {
                text = request
                continue
            }

            return String(text)
        }
        return nil
    }

    /// Codex also derives some index names from the raw first input, where
    /// these wrappers can be flattened or truncated before the request.
    static func isCodexPreambleTitle(_ title: String) -> Bool {
        let text = title.drop(while: \.isWhitespace)
        guard !text.hasPrefix(filesHeading), !text.hasPrefix("<environment_context>") else { return true }
        guard text.hasPrefix(agentsHeading) else { return false }
        let suffix = text.dropFirst(agentsHeading.count)
        return suffix.isEmpty || suffix.first?.isWhitespace == true || suffix.first == ":"
    }

    private static func textAfterAttachments(in text: Substring) -> Substring? {
        var rest = text
        var sawFile = false
        while !rest.isEmpty {
            let (line, remaining) = firstLine(in: rest)
            if line == "## My request:" || line == "## My request" { return remaining }
            if isAttachmentLine(line) {
                sawFile = true
            } else if !sawFile || (line != "Image attachment: true" && line != attachmentNotice) {
                return sawFile ? rest : nil
            }
            rest = remaining
        }
        return sawFile ? rest : nil
    }

    private static func isAttachmentLine(_ line: Substring) -> Bool {
        guard line.hasPrefix("## "), let separator = line.range(of: ": ") else { return false }
        let path = line[separator.upperBound...]
        return path.hasPrefix("/") || path.hasPrefix("~/") || path.hasPrefix("file://")
    }

    private static func firstLine(in text: Substring) -> (Substring, Substring) {
        guard let newline = text.firstIndex(where: \.isNewline) else { return (text, text[text.endIndex...]) }
        return (text[..<newline], text[text.index(after: newline)...].drop(while: \.isWhitespace))
    }

    /// The first thing the user typed, as a preview.
    static func firstTyped(in records: some Sequence<[String: Any]>, source: SessionSource) -> String? {
        records.lazy
            .compactMap { TranscriptFormat.turn(in: $0, source: source) }
            .filter { $0.role == .user }
            .compactMap { preview($0.text) }
            .first
    }

    static func latestTyped(in records: [[String: Any]], source: SessionSource) -> String? {
        firstTyped(in: records.reversed(), source: source)
    }

    /// Looks at the end of the file only when the start has nothing typed,
    /// which happens when tool output fills the start of a transcript.
    static func firstTyped(inHead records: [[String: Any]], of url: URL, source: SessionSource) -> String? {
        firstTyped(in: records, source: source)
            ?? firstTyped(in: JSONLSample.tail(of: url, byteLimit: fallbackByteLimit), source: source)
    }

    /// Joins the text blocks of a message's `content` array.
    static func joinedText(from blocks: [[String: Any]], blockType: String, separator: String = " ") -> String {
        blocks
            .filter { $0["type"] as? String == blockType }
            .compactMap { $0["text"] as? String }
            .joined(separator: separator)
    }
}
