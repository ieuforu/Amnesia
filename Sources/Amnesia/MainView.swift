import AmnesiaCore
import AppKit
import SwiftUI

private enum Theme {
    /// The indigo from the app icon.
    static let brand = Color(red: 0.31, green: 0.29, blue: 0.82)
    static let delete = Color(red: 0.85, green: 0.22, blue: 0.24)
    static let hover = Color.primary.opacity(0.05)
    static let selection = brand.opacity(0.14)
    static let card = Color.primary.opacity(0.045)
    static let cornerRadius: CGFloat = 9
}

/// What the sidebar has selected: a whole agent, or one project within it.
private enum Scope: Hashable {
    case agent(SessionSource)
    case project(SessionSource, path: String?)

    var source: SessionSource {
        switch self {
        case .agent(let source), .project(let source, _): source
        }
    }
}

private enum SortOrder: String, CaseIterable, Identifiable {
    case recent = "Recent"
    case largest = "Largest"
    case name = "Name"

    var id: Self { self }

    func sorted(_ sessions: [Session]) -> [Session] {
        switch self {
        case .recent: sessions.sorted { $0.updatedAt > $1.updatedAt }
        case .largest: sessions.sorted { $0.size > $1.size }
        case .name:
            sessions.sorted { $0.sortTitle.localizedStandardCompare($1.sortTitle) == .orderedAscending }
        }
    }
}

/// The window for looking through sessions before clearing them.
struct MainView: View {
    let store: SessionStore

    @State private var scope = Scope.agent(.claudeCode)
    @State private var selection = ListSelection()
    @State private var sortOrder = SortOrder.recent
    @State private var isConfirmingDelete = false

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(sessions: store.sessions, scope: $scope)
                .frame(width: 236)
            Divider()
            sessionList
                .frame(minWidth: 320, maxWidth: .infinity)
            Divider()
            detail
                .frame(width: 372)
        }
        .ignoresSafeArea(.container, edges: .top)
        .background(Color(nsColor: .textBackgroundColor))
        .task { await store.refresh() }
        .onChange(of: scope) { selection.clear() }
        .onChange(of: store.sessions) { selection.limit(to: Set(store.sessions.map(\.id))) }
        .background {
            // This window has no File menu to provide the shortcut.
            Button("Close Window") { NSApp.keyWindow?.performClose(nil) }
                .keyboardShortcut("w")
                .opacity(0)
        }
        .confirmationDialog(
            "Delete \(sessionCount(deletableSelection)) (\(totalSize(of: deletableSelection)))?",
            isPresented: $isConfirmingDelete
        ) {
            Button("Delete", role: .destructive) {
                let sessions = deletableSelection
                selection.clear()
                Task { await store.delete(sessions) }
            }
        } message: {
            Text(deleteExplanation(for: scope.source))
        }
    }

    // MARK: Data

    private var visibleSessions: [Session] {
        let sessions = store.sessions.filter { session in
            switch scope {
            case .agent(let source): session.source == source
            case .project(let source, let path): session.source == source && session.projectPath == path
            }
        }
        return sortOrder.sorted(sessions)
    }

    private var selectedSessions: [Session] {
        visibleSessions.filter { selection.ids.contains($0.id) }
    }

    /// Sessions in use are never offered for deletion.
    private var deletableSelection: [Session] {
        selectedSessions.filter(\.isDeletable)
    }

    private var title: String {
        switch scope {
        case .agent(let source): source.displayName
        case .project: SessionGroup.grouping(visibleSessions).first?.displayName ?? "Project"
        }
    }

    private func requestDelete() {
        isConfirmingDelete = !deletableSelection.isEmpty
    }

    // MARK: List

    private var sessionList: some View {
        let sessions = visibleSessions
        let ids = sessions.map(\.id)
        let largest = sessions.map(\.size).max() ?? 0

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 20, weight: .semibold))
                        .lineLimit(1)
                    Text("\(sessionCount(sessions).lowercased()) · \(totalSize(of: sessions))")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer(minLength: 12)
                SortControl(selection: $sortOrder)
            }
            .padding(.horizontal, 18)
            .padding(.top, 38)
            .padding(.bottom, 12)

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(sessions) { session in
                        SessionListRow(
                            session: session,
                            showsProject: isShowingWholeAgent,
                            largestSize: largest,
                            isSelected: selection.ids.contains(session.id)
                        ) { click in
                            selection.click(session.id, click, in: ids)
                        }
                        .contextMenu {
                            Button("Show in Finder") { store.reveal(session) }
                            if session.isDeletable {
                                Button("Delete…") {
                                    if !selection.ids.contains(session.id) {
                                        selection.click(session.id, .plain, in: ids)
                                    }
                                    requestDelete()
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }

            if let failure = store.failureMessage {
                Divider()
                Text(failure)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
            }
        }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.upArrow) {
            selection.move(by: -1, in: ids)
            return .handled
        }
        .onKeyPress(.downArrow) {
            selection.move(by: 1, in: ids)
            return .handled
        }
        .onDeleteCommand(perform: requestDelete)
    }

    private var isShowingWholeAgent: Bool {
        if case .agent = scope { true } else { false }
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        switch selectedSessions.count {
        case 0:
            EmptyDetail()
        case 1:
            SessionInspector(session: selectedSessions[0], store: store, onDelete: requestDelete)
                .id(selectedSessions[0].id)
        default:
            MultipleSelectionDetail(
                sessions: selectedSessions,
                deletableCount: deletableSelection.count,
                onDelete: requestDelete
            )
        }
    }
}

/// Dots that thin out toward the end, like the speech bubble in the app icon.
private struct DissolveBar: View {
    let ratio: Double

    private static let dotCount = 18

    var body: some View {
        Canvas { context, size in
            let spacing = size.width / CGFloat(Self.dotCount)
            let diameter = min(spacing * 0.62, size.height)
            let filled = max(1, Int((ratio * Double(Self.dotCount)).rounded(.up)))

            for index in 0..<Self.dotCount {
                let rect = CGRect(
                    x: CGFloat(index) * spacing,
                    y: (size.height - diameter) / 2,
                    width: diameter,
                    height: diameter
                )
                let progress = Double(index) / Double(filled)
                let color =
                    index < filled
                    ? Theme.brand.opacity(1 - pow(progress, 3) * 0.75)
                    : Color.primary.opacity(0.09)
                context.fill(Path(ellipseIn: rect), with: .color(color))
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }
}

// MARK: - Sidebar

private struct Sidebar: View {
    let sessions: [Session]
    @Binding var scope: Scope

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 1) {
                Text(totalSize(of: sessions))
                    .font(.system(size: 26, weight: .semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.25), value: sessions.count)
                Text("stored on this Mac")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18)
            .padding(.top, 48)
            .padding(.bottom, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(SessionSource.allCases) { source in
                        agentSection(source)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 12)
            }
        }
        .background {
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                LinearGradient(
                    colors: [Theme.brand.opacity(0.13), Theme.brand.opacity(0.02)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
    }

    private func agentSection(_ source: SessionSource) -> some View {
        let own = sessions.filter { $0.source == source }
        let groups = SessionGroup.grouping(own)
        let largest = groups.map(\.totalSize).max() ?? 0

        return VStack(alignment: .leading, spacing: 2) {
            SidebarRow(
                title: source.displayName,
                detail: totalSize(of: own),
                isEmphasized: true,
                isSelected: scope == .agent(source)
            ) {
                scope = .agent(source)
            }

            ForEach(groups) { group in
                SidebarRow(
                    title: group.displayName,
                    detail: group.totalSize.formatted(.byteCount(style: .file)),
                    ratio: largest > 0 ? Double(group.totalSize) / Double(largest) : 0,
                    isSelected: scope == .project(source, path: group.projectPath)
                ) {
                    scope = .project(source, path: group.projectPath)
                }
                .help(group.displayPath)
            }
        }
    }
}

private struct SidebarRow: View {
    let title: String
    let detail: String
    var ratio: Double?
    var isEmphasized = false
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(title)
                        .font(.system(size: 13, weight: isEmphasized ? .semibold : .regular))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                if let ratio {
                    DissolveBar(ratio: ratio)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            isSelected ? Theme.selection : (isHovered ? Theme.hover : .clear),
            in: RoundedRectangle(cornerRadius: Theme.cornerRadius)
        )
        .onHover { isHovered = $0 }
    }
}

// MARK: - List

private struct SortControl: View {
    @Binding var selection: SortOrder

    var body: some View {
        HStack(spacing: 2) {
            ForEach(SortOrder.allCases) { order in
                Button {
                    withAnimation(.snappy(duration: 0.2)) { selection = order }
                } label: {
                    Text(order.rawValue)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(order == selection ? .primary : .secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(
                            order == selection ? Theme.selection : .clear,
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(order == selection ? .isSelected : [])
            }
        }
    }
}

private struct SessionListRow: View {
    let session: Session
    let showsProject: Bool
    let largestSize: Int64
    let isSelected: Bool
    let onClick: (ListSelection.Click) -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(session.title ?? "No Message")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(session.title == nil ? .secondary : .primary)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    if !session.isDeletable {
                        Circle()
                            .fill(.green)
                            .frame(width: 6, height: 6)
                        Text("In use")
                        Text("·")
                    }
                    if showsProject {
                        Text(SessionGroup.grouping([session]).first?.displayName ?? "")
                            .lineLimit(1)
                        Text("·")
                    }
                    Text(session.updatedAt, format: .relative(presentation: .named))
                }
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 5) {
                Text(session.size.formatted(.byteCount(style: .file)))
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                DissolveBar(ratio: largestSize > 0 ? Double(session.size) / Double(largestSize) : 0)
                    .frame(width: 72)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .background(
            isSelected ? Theme.selection : (isHovered ? Theme.hover : .clear),
            in: RoundedRectangle(cornerRadius: Theme.cornerRadius)
        )
        .onHover { isHovered = $0 }
        .onTapGesture { onClick(Self.currentClick) }
    }

    private static var currentClick: ListSelection.Click {
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) { return .toggle }
        if flags.contains(.shift) { return .extend }
        return .plain
    }
}

// MARK: - Detail

private struct EmptyDetail: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "text.bubble")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Theme.brand)
                .padding(.bottom, 6)
            Text("Pick a session")
                .font(.system(size: 14, weight: .semibold))
            Text("See what it holds and where it's stored before you clear it.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 220)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct MultipleSelectionDetail: View {
    let sessions: [Session]
    let deletableCount: Int
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            Text(totalSize(of: sessions))
                .font(.system(size: 28, weight: .semibold))
                .monospacedDigit()
            Text("in \(sessionCount(sessions).lowercased())")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            if deletableCount < sessions.count {
                Text("Sessions in use will be kept")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Button("Delete…", action: onDelete)
                .buttonStyle(DeleteButtonStyle())
                .disabled(deletableCount == 0)
                .padding(.top, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SessionInspector: View {
    let session: Session
    let store: SessionStore
    let onDelete: () -> Void

    @State private var detail: SessionDetail?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            transcript
            files
            actions
        }
        .task { detail = await store.detail(for: session) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(session.title ?? "No Message")
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(2)
            HStack(spacing: 4) {
                Text(session.source.displayName)
                Text("·")
                Text(session.updatedAt, format: .relative(presentation: .named))
                Text("·")
                Text(session.size.formatted(.byteCount(style: .file)))
            }
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.top, 40)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var transcript: some View {
        if let messages = detail?.messages, !messages.isEmpty {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(messages) { message in
                        if message.id == detail?.omittedAfter {
                            Text("The middle of this session isn't shown")
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 4)
                        }
                        MessageBubble(message: message)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 6)
            }
        } else {
            Text(detail == nil ? "Loading…" : "No preview")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var files: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("On disk")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                ForEach(detail?.files ?? []) { file in
                    FileRow(file: file)
                }
            }
            .padding(10)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
    }

    private var actions: some View {
        HStack {
            Button("Show in Finder") { store.reveal(session) }
                .buttonStyle(QuietButtonStyle())
            Spacer()
            if session.isDeletable {
                Button("Delete…", action: onDelete)
                    .buttonStyle(DeleteButtonStyle())
            } else {
                HStack(spacing: 6) {
                    Circle()
                        .fill(.green)
                        .frame(width: 6, height: 6)
                    Text("In use")
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            }
        }
        .padding(18)
    }
}

/// Your messages sit on the right in the brand color, like a chat you sent.
private struct MessageBubble: View {
    let message: TranscriptMessage

    private var isUser: Bool { message.role == .user }

    var body: some View {
        Text(message.text)
            .font(.system(size: 12.5))
            .lineSpacing(2)
            .textSelection(.enabled)
            .foregroundStyle(isUser ? Color.white : Color.primary)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(
                isUser ? Theme.brand : Theme.card,
                in: RoundedRectangle(cornerRadius: 12)
            )
            .frame(maxWidth: 280, alignment: isUser ? .trailing : .leading)
            .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }
}

private struct FileRow: View {
    let file: StoredFile

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(file.label)
                    .font(.system(size: 12, weight: .medium))
                Spacer(minLength: 8)
                Text(file.size.formatted(.byteCount(style: .file)))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Text(file.path)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .help(file.path)
        }
    }
}

private struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 7))
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

private struct DeleteButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Theme.delete, in: RoundedRectangle(cornerRadius: 7))
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
    }
}

private func totalSize(of sessions: [Session]) -> String {
    sessions.reduce(0) { $0 + $1.size }.formatted(.byteCount(style: .file))
}
