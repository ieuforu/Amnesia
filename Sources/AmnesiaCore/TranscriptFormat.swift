/// The one definition of which transcript records are conversation turns, as
/// opposed to tool calls, reasoning, subagents and injected context.
enum TranscriptFormat {
    typealias Turn = (role: TranscriptMessage.Role, text: String)

    static func turn(in record: [String: Any], source: SessionSource) -> Turn? {
        switch source {
        case .claudeCode:
            guard let turn = claudeTurn(in: record), !turn.text.drop(while: \.isWhitespace).hasPrefix("<")
            else { return nil }
            return turn
        case .codex:
            return codexTurn(in: record)
        }
    }

    private static func claudeTurn(in record: [String: Any]) -> Turn? {
        guard
            record["isMeta"] as? Bool != true,
            record["isSidechain"] as? Bool != true,
            let message = record["message"] as? [String: Any]
        else { return nil }

        switch record["type"] as? String {
        case "user":
            switch message["content"] {
            case let text as String:
                return (.user, text)
            case let blocks as [[String: Any]]:
                return (.user, MessageText.joinedText(from: blocks, blockType: "text"))
            default:
                return nil
            }
        case "assistant":
            guard let blocks = message["content"] as? [[String: Any]] else { return nil }
            return (.agent, MessageText.joinedText(from: blocks, blockType: "text"))
        default:
            return nil
        }
    }

    private static func codexTurn(in record: [String: Any]) -> Turn? {
        guard
            record["type"] as? String == "response_item",
            let payload = record["payload"] as? [String: Any],
            payload["type"] as? String == "message",
            let blocks = payload["content"] as? [[String: Any]]
        else { return nil }

        switch payload["role"] as? String {
        case "user":
            let text = MessageText.joinedText(from: blocks, blockType: "input_text", separator: "\n\n")
            guard let request = MessageText.codexUserText(text) else { return nil }
            return (.user, request)
        case "assistant":
            return (.agent, MessageText.joinedText(from: blocks, blockType: "output_text", separator: "\n\n"))
        default: return nil
        }
    }
}
