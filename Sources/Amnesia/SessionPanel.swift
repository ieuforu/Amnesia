import AmnesiaCore
import SwiftUI

/// The menu bar panel. It draws no background of its own, so the system's
/// glass shows through, and follows the layout of native menu bar menus.
///
/// It only displays what it is given, so it can render sample data as easily
/// as real sessions.
struct SessionPanel: View {
    let sessions: [Session]
    let leftovers: [Leftover]
    let isBusy: Bool
    let failureMessage: String?
    let onReveal: (Session) -> Void
    let onDelete: ([Session]) -> Void
    let onCleanLeftovers: ([Leftover]) -> Void
    let onOpenWindow: () -> Void

    @AppStorage("selectedSource") private var selectedSource = SessionSource.claudeCode
    @State private var selectedIDs: Set<String> = []
    @State private var isConfirmingDelete = false
    /// The row asking to confirm its own delete, so the choice stays under the
    /// pointer instead of moving to the footer.
    @State private var confirmingRowID: String?
    @State private var isConfirmingCleanup = false
    @State private var listHeight: CGFloat = 0

    private static let maxListHeight: CGFloat = 440
    private static let staleDays = 30

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
                .foregroundStyle(.panelSecondary)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.25), value: summary)
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
            confirmingRowID = nil
            isConfirmingCleanup = false
        }
    }

    private func sessions(from source: SessionSource) -> [Session] {
        sessions.filter { $0.source == source }
    }

    private var summary: String {
        let visible = sessions(from: selectedSource)
        return "\(visible.count) · \(totalSize(of: visible))"
    }

    /// Sessions that started running after being checked don't count.
    private var selectedSessions: [Session] {
        sessions(from: selectedSource).filter { selectedIDs.contains($0.id) && $0.isDeletable }
    }

    private var staleSessions: [Session] {
        sessions(from: selectedSource).filter { $0.isDeletable && $0.isOlder(thanDays: Self.staleDays) }
    }

    private func delete(_ session: Session) {
        confirmingRowID = nil
        onDelete([session])
    }

    private func totalSize(of sessions: [Session]) -> String {
        sessions.reduce(0) { $0 + $1.size }.formatted(.byteCount(style: .file))
    }

    private var visibleLeftovers: [Leftover] {
        leftovers.filter { $0.source == selectedSource }
    }

    private var groups: [SessionGroup] {
        SessionGroup.grouping(sessions(from: selectedSource))
    }

    @ViewBuilder
    private var content: some View {
        if groups.isEmpty, visibleLeftovers.isEmpty {
            Text(isBusy ? "Scanning…" : "No Sessions")
                .font(.system(size: 13))
                .foregroundStyle(.panelSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(groups) { group in
                        SessionGroupView(
                            group: group,
                            selectedIDs: $selectedIDs,
                            confirmingRowID: $confirmingRowID,
                            isBusy: isBusy,
                            onReveal: onReveal,
                            onDelete: delete
                        )
                        .transition(.opacity)
                    }
                    if !visibleLeftovers.isEmpty {
                        LeftoversView(leftovers: visibleLeftovers)
                    }
                }
                .animation(.easeOut(duration: 0.18), value: groups.flatMap { $0.sessions.map(\.id) })
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { listHeight = $0 }
            }
            .onChange(of: selectedIDs) { confirmingRowID = nil }
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
                .foregroundStyle(.panelSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.bottom, 5)
        }

        if isConfirmingDelete, !selectedSessions.isEmpty {
            Confirmation(
                title: "Delete \(sessionCount(selectedSessions)) (\(totalSize(of: selectedSessions)))?",
                explanation: deleteExplanation(for: selectedSource),
                actionTitle: "Delete",
                isBusy: isBusy,
                onCancel: { isConfirmingDelete = false },
                onConfirm: {
                    onDelete(selectedSessions)
                    selectedIDs = []
                    isConfirmingDelete = false
                }
            )
        } else if isConfirmingCleanup, !visibleLeftovers.isEmpty {
            Confirmation(
                title: "Clean Up Leftovers?",
                explanation: """
                    Prompts and files from \(sessionCount(visibleLeftovers).lowercased()) that no longer \
                    exist are removed for good. They can't be recovered and won't appear in \
                    your prompt history.
                    """,
                actionTitle: "Clean Up",
                isBusy: isBusy,
                onCancel: { isConfirmingCleanup = false },
                onConfirm: {
                    onCleanLeftovers(visibleLeftovers)
                    isConfirmingCleanup = false
                }
            )
        } else {
            VStack(spacing: 0) {
                if selectedSessions.isEmpty {
                    if !staleSessions.isEmpty {
                        MenuRow(title: "Select Older Than \(Self.staleDays) Days") {
                            selectedIDs = Set(staleSessions.map(\.id))
                        }
                    }
                    if !visibleLeftovers.isEmpty {
                        MenuRow(title: "Clean Up Leftovers…") {
                            isConfirmingCleanup = true
                        }
                    }
                } else {
                    MenuRow(title: "Delete \(sessionCount(selectedSessions))…") {
                        isConfirmingDelete = true
                    }
                    MenuRow(title: "Deselect All") {
                        selectedIDs = []
                    }
                }
                MenuRow(title: "Open Amnesia App", action: onOpenWindow)
                MenuRow(title: "Quit Amnesia") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        }
    }

}

func sessionCount(_ items: some Collection) -> String {
    items.count == 1 ? "1 Session" : "\(items.count) Sessions"
}

func deleteExplanation(for source: SessionSource) -> String {
    let common = """
        Transcripts move to the Trash and stay on this Mac until you empty it. \
        Prompt history and related records are removed for good.
        """
    switch source {
    case .claudeCode: return common
    case .codex: return common + " Codex sessions can't be resumed after this."
    }
}

/// Confirms inside the panel, because a separate alert would take focus and
/// close the menu bar panel.
private struct Confirmation: View {
    let title: String
    let explanation: String
    let actionTitle: String
    let isBusy: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .bold))

            Text(explanation)
                .font(.system(size: 11))
                .foregroundStyle(.panelSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(actionTitle, role: .destructive, action: onConfirm)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
            }
            .disabled(isBusy)
            .padding(.top, 2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
    }
}

/// Summarizes leftovers as one row, because they're cleaned up together.
private struct LeftoversView: View {
    let leftovers: [Leftover]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Leftovers")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.panelSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 3)

            VStack(alignment: .leading, spacing: 1) {
                Text(leftovers.count == 1 ? "1 deleted session" : "\(leftovers.count) deleted sessions")
                    .font(.system(size: 13))

                Text(details)
                    .font(.system(size: 11))
                    .foregroundStyle(.panelSecondary)
                    .monospacedDigit()
            }
            .padding(.leading, 32)
            .padding(.trailing, 14)
            .padding(.vertical, 4)
            .help("Their transcripts are gone, but these records remain.")
        }
    }

    private var details: String {
        let prompts = leftovers.reduce(0) { $0 + $1.promptCount }
        let size = leftovers.reduce(0) { $0 + $1.size }

        var parts: [String] = []
        if prompts > 0 {
            parts.append(prompts == 1 ? "1 prompt" : "\(prompts) prompts")
        }
        if size > 0 {
            parts.append(size.formatted(.byteCount(style: .file)))
        }
        // Database records have no size of their own to report.
        if leftovers.contains(where: \.hasDatabaseRecord) {
            parts.append("database records")
        }
        return parts.joined(separator: " · ")
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
    @Binding var confirmingRowID: String?
    let isBusy: Bool
    let onReveal: (Session) -> Void
    let onDelete: (Session) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggleGroup) {
                HStack(spacing: 8) {
                    Text(group.displayName)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if selectedCount > 0 {
                        Text("\(selectedCount) of \(group.deletableIDs.count)")
                            .monospacedDigit()
                    }
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.panelSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 3)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(group.deletableIDs.isEmpty)
            .modifier(HoverHighlight())
            .help("\(group.displayPath) — click to select or deselect all")

            ForEach(group.sessions) { session in
                SessionRow(
                    session: session,
                    isSelected: selectedIDs.contains(session.id),
                    alwaysShowsCheckbox: !selectedIDs.isEmpty,
                    onToggle: { selectedIDs.formSymmetricDifference([session.id]) },
                    isConfirmingDelete: confirmingRowID == session.id,
                    isBusy: isBusy,
                    onReveal: { onReveal(session) },
                    onRequestDelete: { setConfirmingRow(session.id) },
                    onCancelDelete: { setConfirmingRow(nil) },
                    onDelete: { onDelete(session) }
                )
                .transition(.opacity)
            }
        }
    }

    private func setConfirmingRow(_ id: String?) {
        withAnimation(.snappy(duration: 0.2)) {
            confirmingRowID = id
        }
    }

    private var selectedCount: Int {
        group.deletableIDs.intersection(selectedIDs).count
    }

    private func toggleGroup() {
        if selectedCount == group.deletableIDs.count {
            selectedIDs.subtract(group.deletableIDs)
        } else {
            selectedIDs.formUnion(group.deletableIDs)
        }
    }
}

private struct SessionRow: View {
    let session: Session
    let isSelected: Bool
    let alwaysShowsCheckbox: Bool
    let onToggle: () -> Void
    let isConfirmingDelete: Bool
    let isBusy: Bool
    let onReveal: () -> Void
    let onRequestDelete: () -> Void
    let onCancelDelete: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    private static let hoverFade = Animation.easeOut(duration: 0.12)

    var body: some View {
        HStack(spacing: 6) {
            checkbox

            Button(action: onReveal) {
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(session.title ?? "No Message")
                            .font(.system(size: 13))
                            .foregroundStyle(session.title == nil ? Color.panelSecondary : Color.primary)
                            .lineLimit(1)

                        ZStack(alignment: .leading) {
                            if isConfirmingDelete {
                                Text(deleteWarning)
                                    .transition(.opacity)
                            } else {
                                HStack(spacing: 4) {
                                    Text(session.updatedAt, format: .relative(presentation: .named))
                                    Text("·")
                                    Text(session.size.formatted(.byteCount(style: .file)))
                                }
                                .transition(.opacity)
                            }
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(.panelSecondary)
                        .monospacedDigit()
                        .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Show in Finder")

            trailingControl
        }
        .padding(.leading, 10)
        .padding(.trailing, 14)
        .padding(.vertical, 4)
        .modifier(HoverHighlight())
        .onHover { isHovered = $0 }
    }

    private var deleteWarning: String {
        switch session.source {
        case .claudeCode: "Its prompts are removed for good"
        case .codex: "It can't be resumed after this"
        }
    }

    /// The trash button stays hidden rather than removed while idle, so hovering
    /// never shifts the row. It also hides during a selection, which the footer
    /// acts on.
    @ViewBuilder
    private var trailingControl: some View {
        if !session.isDeletable {
            Circle()
                .fill(.green)
                .frame(width: 7, height: 7)
                .frame(width: 16, height: 16)
                .help("In use")
                .accessibilityLabel("In use")
        } else if isConfirmingDelete {
            Button("Delete", role: .destructive, action: onDelete)
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.small)
                .disabled(isBusy)
                .transition(.move(edge: .trailing).combined(with: .opacity))

            // Takes the trash button's exact spot, so an accidental double
            // click cancels instead of deleting.
            iconButton("xmark", label: "Cancel", action: onCancelDelete)
                .keyboardShortcut(.cancelAction)
                .transition(.opacity)
        } else {
            iconButton("trash", label: "Delete", action: onRequestDelete)
                .opacity(isHovered && !alwaysShowsCheckbox ? 1 : 0)
                .animation(Self.hoverFade, value: isHovered)
                .disabled(alwaysShowsCheckbox)
                .transition(.opacity)
        }
    }

    private func iconButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .foregroundStyle(.panelSecondary)
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }

    /// Sessions in use have no checkbox, because they can't be deleted.
    @ViewBuilder
    private var checkbox: some View {
        if !session.isDeletable {
            Color.clear.frame(width: 16, height: 16)
        } else {
            Button(action: onToggle) {
                circle
                    .font(.system(size: 14))
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(isHovered || isSelected || alwaysShowsCheckbox ? 1 : 0)
            .animation(Self.hoverFade, value: isHovered)
            .accessibilityLabel(isSelected ? "Deselect" : "Select")
        }
    }

    /// The filled symbol uses an opaque white mark, because its default cut-out
    /// mark lets the glass show through and is hard to see.
    private var circle: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .symbolRenderingMode(.palette)
            .foregroundStyle(
                isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.panelSecondary),
                AnyShapeStyle(.tint)
            )
            .contentTransition(.symbolEffect(.replace))
            .animation(.snappy(duration: 0.15), value: isSelected)
    }
}

extension ShapeStyle where Self == Color {
    /// Darker than the system secondary style, which washes out on glass when
    /// something bright sits behind the panel.
    fileprivate static var panelSecondary: Color { .primary.opacity(0.72) }
}

extension SessionSource {
    fileprivate var tabTitle: String {
        switch self {
        case .claudeCode: "Claude"
        case .codex: "Codex"
        }
    }
}
