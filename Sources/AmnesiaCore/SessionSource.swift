/// A coding agent whose local sessions Amnesia can manage.
public enum SessionSource: String, CaseIterable, Identifiable, Sendable {
    case claudeCode
    case codex

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        }
    }
}
