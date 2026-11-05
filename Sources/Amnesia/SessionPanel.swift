import AmnesiaCore
import SwiftUI

/// The menu bar panel. It draws no background of its own, so the system's
/// glass shows through, and follows the layout of native menu bar menus.
///
/// It only displays what it is given, so it can render sample data as easily
/// as real sessions.
struct SessionPanel: View {
    let sessions: [Session]
    let isBusy: Bool
    let failureMessage: String?
    let onRefresh: () -> Void
    let onReveal: (Session) -> Void
    let onDelete: ([Session]) -> Void

    @AppStorage("selectedSource") private var selectedSource = SessionSource.claudeCode
    @State private var selectedIDs: Set<String> = []
    @State private var isConfirmingDelete = false
    @State private var listHeight: CGFloat = 0

    private static let maxListHeight: CGFloat = 440

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            sourcePicker
            PanelDivider()
            content
            PanelDivider()
            actions
        }
        .padding(.vertical, 6)
        .frame(width: 340)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Amnesia")
                .font(.system(size: 13, weight: .bold))
            Spacer()
            Text(summary)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    private var sourcePicker: some View {
        Picker("Source", selection: $selectedSource) {
            ForEach(SessionSource.allCases) { source in
                Text("\(source.tabTitle)  \(sessions(from: source).count)").tag(source)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 14)
        .padding(.top, 2)
        .padding(.bottom, 4)
        .onChange(of: selectedSource) {
            // Selection stays within one agent, so a delete can't span both.
            selectedIDs = []
            isConfirmingDelete = false
        }
    }

    private func sessions(from source: SessionSource) -> [Session] {
        sessions.filter { $0.source == source }
    }

    private var summary: String {
        let visible = sessions(from: selectedSource)
        let size = visible.reduce(0) { $0 + $1.size }
        return "\(visible.count) · \(size.formatted(.byteCount(style: .file)))"
    }

    /// Sessions that started running after being checked don't count.
    private var selectedSessions: [Session] {
        sessions(from: selectedSource).filter { selectedIDs.contains($0.id) && !$0.isActive }
    }

    private var groups: [SessionGroup] {
        SessionGroup.grouping(sessions(from: selectedSource))
    }

    @ViewBuilder
    private var content: some View {
        if groups.isEmpty {
            Text(isBusy ? "Scanning…" : "No Sessions")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(groups) { group in
                        SessionGroupView(
                            group: group,
                            selectedIDs: $selectedIDs,
                            onReveal: onReveal
                        )
                    }
                }
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { listHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.never)
            // Fit short lists exactly, and scroll long ones.
            .frame(height: min(listHeight, Self.maxListHeight))
        }
    }

    @ViewBuilder
    private var actions: some View {
        if let failureMessage {
            Text(failureMessage)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.bottom, 5)
        }

        if isConfirmingDelete, !selectedSessions.isEmpty {
            DeleteConfirmation(
                sessions: selectedSessions,
                source: selectedSource,
                isBusy: isBusy,
                onCancel: { isConfirmingDelete = false },
                onDelete: {
                    onDelete(selectedSessions)
                    selectedIDs = []
                    isConfirmingDelete = false
                }
            )
        } else {
            VStack(spacing: 0) {
                if selectedSessions.isEmpty {
                    MenuRow(title: "Refresh", action: onRefresh)
                        .keyboardShortcut("r")
                        .disabled(isBusy)
                } else {
                    MenuRow(title: "Delete \(sessionCount(selectedSessions))…") {
                        isConfirmingDelete = true
                    }
                }
                MenuRow(title: "Quit Amnesia") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        }
    }
}

private func sessionCount(_ sessions: [Session]) -> String {
    sessions.count == 1 ? "1 Session" : "\(sessions.count) Sessions"
}

/// Confirms inside the panel, because a separate alert would take focus and
/// close the menu bar panel.
private struct DeleteConfirmation: View {
    let sessions: [Session]
    let source: SessionSource
    let isBusy: Bool
    let onCancel: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Delete \(sessionCount(sessions))?")
                .font(.system(size: 13, weight: .bold))

            Text(explanation)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Delete", role: .destructive, action: onDelete)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
            }
            .disabled(isBusy)
            .padding(.top, 2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
    }

    private var explanation: String {
        let common = """
            Transcripts move to the Trash and stay on this Mac until you empty it. \
            Prompt history and related records are removed for good.
            """
        switch source {
        case .claudeCode: return common
        case .codex: return common + " Codex sessions can't be resumed after this."
        }
    }
}

private struct PanelDivider: View {
    var body: some View {
        Divider()
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
    }
}

/// Highlights its content while hovered, like a menu item.
private struct HoverHighlight: ViewModifier {
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.primary.opacity(isHovered ? 0.1 : 0))
                    .padding(.horizontal, 6)
            )
            .onHover { isHovered = $0 }
    }
}

private struct MenuRow: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(HoverHighlight())
    }
}

private struct SessionGroupView: View {
    let group: SessionGroup
    @Binding var selectedIDs: Set<String>
    let onReveal: (Session) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 3)
                .help(fullPath)

            ForEach(group.sessions) { session in
                SessionRow(
                    session: session,
                    isSelected: selectedIDs.contains(session.id),
                    alwaysShowsCheckbox: !selectedIDs.isEmpty,
                    onToggle: { selectedIDs.formSymmetricDifference([session.id]) },
                    onReveal: { onReveal(session) }
                )
            }
        }
    }

    private var fullPath: String {
        guard let path = group.projectPath else { return "Unknown Project" }
        return (path as NSString).abbreviatingWithTildeInPath
    }

    private var title: String {
        switch fullPath {
        case "~": "Home"
        default: (fullPath as NSString).lastPathComponent
        }
    }
}

private struct SessionRow: View {
    let session: Session
    let isSelected: Bool
    let alwaysShowsCheckbox: Bool
    let onToggle: () -> Void
    let onReveal: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            checkbox

            Button(action: onReveal) {
                HStack(spacing: 9) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(session.firstMessage ?? "No Message")
                            .font(.system(size: 13))
                            .foregroundStyle(session.firstMessage == nil ? .secondary : .primary)
                            .lineLimit(1)

                        HStack(spacing: 4) {
                            Text(session.updatedAt, format: .relative(presentation: .named))
                            Text("·")
                            Text(session.size.formatted(.byteCount(style: .file)))
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    }

                    Spacer(minLength: 0)

                    if session.isActive {
                        Circle()
                            .fill(.green)
                            .frame(width: 7, height: 7)
                            .help("In use")
                            .accessibilityLabel("In use")
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Show in Finder")
        }
        .padding(.leading, 10)
        .padding(.trailing, 14)
        .padding(.vertical, 4)
        .modifier(HoverHighlight())
        .onHover { isHovered = $0 }
    }

    /// Sessions in use have no checkbox, because they can't be deleted.
    @ViewBuilder
    private var checkbox: some View {
        if session.isActive {
            Color.clear.frame(width: 16, height: 16)
        } else {
            Button(action: onToggle) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(isHovered || isSelected || alwaysShowsCheckbox ? 1 : 0)
            .accessibilityLabel(isSelected ? "Deselect" : "Select")
        }
    }
}

extension SessionSource {
    fileprivate var tabTitle: String {
        switch self {
        case .claudeCode: "Claude"
        case .codex: "Codex"
        }
    }
}
