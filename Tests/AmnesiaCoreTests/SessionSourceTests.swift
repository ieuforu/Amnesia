import Testing

@testable import AmnesiaCore

@Test func everySourceHasADisplayName() {
    #expect(SessionSource.allCases.map(\.displayName) == ["Claude Code", "Codex"])
}
