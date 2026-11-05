/// The one definition of which transcript records are conversation turns, as
/// opposed to tool calls, reasoning, subagents and injected context.
enum TranscriptFormat {
    typealias Turn = (role: TranscriptMessage.Role, text: String)

    static func turn(in record: [String: Any], source: SessionSource) -> Turn? {
        let turn =
            switch source {
            case .claudeCode: claudeTurn(in: record)
            case .codex: codexTurn(in: record)
            }
        guard let turn, !MessageText.isInjected(turn.text) else { return nil }
        return turn
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
        case "user": return (.user, MessageText.joinedText(from: blocks, blockType: "input_text"))
        case "assistant": return (.agent, MessageText.joinedText(from: blocks, blockType: "output_text"))
        default: return nil
        }
    }
}
