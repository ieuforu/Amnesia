import AmnesiaCore
import AppKit
import SwiftUI

extension Color {
    fileprivate init(light: NSColor, dark: NSColor) {
        self.init(
            nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            }
        )
    }
}

private enum Theme {
    /// The indigo from the app icon, lifted in dark mode so text stays readable.
    static let brand = Color(
        light: NSColor(red: 0.31, green: 0.29, blue: 0.82, alpha: 1),
        dark: NSColor(red: 0.64, green: 0.63, blue: 1, alpha: 1)
    )
    static let delete = Color(
        light: NSColor(red: 0.82, green: 0.2, blue: 0.22, alpha: 1),
        dark: NSColor(red: 1, green: 0.47, blue: 0.47, alpha: 1)
    )
    static let header = Color(light: NSColor(white: 0.945, alpha: 1), dark: NSColor(white: 0.09, alpha: 1))
    static let sheet = Color(light: .white, dark: NSColor(white: 0.135, alpha: 1))
    static let card = Color.primary.opacity(0.04)
    static let sheetRadius: CGFloat = 22
    static let cardRadius: CGFloat = 16
    static let panelRadius: CGFloat = 18
    /// Just under half the 30pt height: outlining fully rounded ends leaves
    /// small spikes where the two arcs meet.
    static let pillRadius: CGFloat = 13
    static let number = Font.system(size: 22, weight: .regular, design: .monospaced)
    static let caption = Font.system(size: 12, design: .monospaced)
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

    func sorted(_ groups: [SessionGroup]) -> [SessionGroup] {
        switch self {
        case .recent: groups
        case .largest: groups.sorted { $0.totalSize > $1.totalSize }
        case .name:
            groups.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        }
    }
}

/// Where a delete has got to. Dragging and the Delete button both lead here.
private enum DeleteFlow: Equatable {
    case idle
    case confirming([Session])
    case deleting([Session])
    case finished(freed: String)
}

/// A session being dragged toward the delete zone.
private struct CardDrag: Equatable {
    var sessions: [Session]
    var location: CGPoint
    var isOverZone: Bool
}

/// The window for looking through sessions before clearing them: a gray header
/// holding a white sheet, with sessions as cards grouped by project.
struct MainView: View {
    let store: SessionStore

    @State private var source = SessionSource.claudeCode
    @State private var selection = ListSelection()
    @State private var sortOrder = SortOrder.recent
    @State private var collapsedGroups: Set<String> = []
    @State private var deleteFlow = DeleteFlow.idle
    @State private var drag: CardDrag?
    @State private var detailFrame = CGRect.zero
    @Namespace private var chips
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let windowSpace = "window"
    private static let morph = Animation.snappy(duration: 0.32)

    var body: some View {
        VStack(spacing: 0) {
            header

            HStack(alignment: .top, spacing: 14) {
                sessionsPane
                    .frame(minWidth: 320, maxWidth: .infinity)
                detailPanel
            }
            .padding(14)
            .background(
                Theme.sheet,
                in: UnevenRoundedRectangle(
                    topLeadingRadius: Theme.sheetRadius,
                    topTrailingRadius: Theme.sheetRadius
                )
            )
        }
        .ignoresSafeArea(.container, edges: .top)
        .background(Theme.header)
        .task { await store.refresh() }
        .onChange(of: source) { selection.clear() }
        .onChange(of: store.sessions) { selection.limit(to: Set(store.sessions.map(\.id))) }
        .background {
            // This window has no File menu to provide the shortcut.
            Button("Close Window") { NSApp.keyWindow?.performClose(nil) }
                .keyboardShortcut("w")
                .opacity(0)
        }
        .coordinateSpace(name: Self.windowSpace)
        .overlay(alignment: .topLeading) {
            if let drag {
                DragGhost(sessions: drag.sessions, isOverZone: drag.isOverZone)
                    .position(drag.location)
                    .allowsHitTesting(false)
                    .transition(.opacity.combined(with: .scale(scale: 0.7)))
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Amnesia")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(sessionCount(store.sessions).lowercased()) · \(totalSize(of: store.sessions))")
                .font(Theme.caption)
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.25), value: store.sessions.count)
        }
        // Clears the window's close, minimize and zoom buttons.
        .padding(.leading, 84)
        .padding(.trailing, 22)
        .frame(height: 48)
    }

    // MARK: Data

    private var groups: [SessionGroup] {
        let sessions = store.sessions.filter { $0.source == source }
        return sortOrder.sorted(SessionGroup.grouping(sessions))
    }

    /// Sessions in on-screen order, which clicks and arrow keys follow.
    private var orderedSessions: [Session] {
        groups
            .filter { !collapsedGroups.contains($0.id) }
            .flatMap { sortOrder.sorted($0.sessions) }
    }

    private var selectedSessions: [Session] {
        store.sessions.filter { selection.ids.contains($0.id) }
    }

    /// Sessions in use are never offered for deletion.
    private var deletableSelection: [Session] {
        selectedSessions.filter(\.isDeletable)
    }

    private func requestDelete() {
        guard !deletableSelection.isEmpty, deleteFlow == .idle else { return }
        withAnimation(Self.morph) { deleteFlow = .confirming(deletableSelection) }
    }

    /// The card is shredded first and removed for real afterwards, so a session
    /// that fails to delete can simply reappear with its reason.
    private func delete(_ sessions: [Session]) {
        withAnimation(Self.morph) { deleteFlow = .deleting(sessions) }

        Task {
            if !reduceMotion {
                try? await Task.sleep(for: .seconds(Shredded<EmptyView>.duration))
            }
            selection.clear()
            await store.delete(sessions)

            if store.failureMessage == nil {
                withAnimation(Self.morph) { deleteFlow = .finished(freed: totalSize(of: sessions)) }
                try? await Task.sleep(for: .seconds(1.4))
            }
            withAnimation(Self.morph) { deleteFlow = .idle }
        }
    }

    private var shreddingIDs: Set<String> {
        if case .deleting(let sessions) = deleteFlow { Set(sessions.map(\.id)) } else { [] }
    }

    // MARK: Dragging

    private func dragChanged(_ session: Session, to location: CGPoint) {
        guard deleteFlow == .idle else { return }

        let isOverZone = detailFrame.insetBy(dx: -10, dy: -10).contains(location)
        if drag == nil {
            // Dragging a selected card carries the rest of the selection with it.
            let sessions = selection.ids.contains(session.id) ? deletableSelection : [session]
            guard session.isDeletable, !sessions.isEmpty else { return }
            withAnimation(Self.morph) {
                drag = CardDrag(sessions: sessions, location: location, isOverZone: isOverZone)
            }
        } else {
            drag?.location = location
            if drag?.isOverZone != isOverZone {
                withAnimation(Self.morph) { drag?.isOverZone = isOverZone }
            }
        }
    }

    private func dragEnded() {
        guard let finished = drag else { return }
        withAnimation(Self.morph) {
            drag = nil
            if finished.isOverZone {
                deleteFlow = .confirming(finished.sessions)
            }
        }
    }

    // MARK: Sessions

    private var sessionsPane: some View {
        let ids = orderedSessions.map(\.id)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ForEach(SessionSource.allCases) { option in
                    Chip(title: option.displayName, isSelected: option == source, namespace: chips) {
                        withAnimation(Self.morph) { source = option }
                    }
                }
                SortChip(selection: $sortOrder)
                Spacer()
            }
            .padding(.top, 2)
            .padding(.horizontal, 4)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(groups) { group in
                        groupSection(group, orderedIDs: ids)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 8)
                .animation(Self.morph, value: sortOrder)
                .animation(Self.morph, value: store.sessions.map(\.id))
            }
            .scrollIndicators(.never)

            if let failure = store.failureMessage {
                Text(failure)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
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

    private func groupSection(_ group: SessionGroup, orderedIDs: [String]) -> some View {
        let isCollapsed = collapsedGroups.contains(group.id)

        return VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.snappy(duration: 0.2)) {
                    collapsedGroups.formSymmetricDifference([group.id])
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .medium))
                        .rotationEffect(.degrees(isCollapsed ? -90 : 0))
                    Text(group.displayName)
                        .font(.system(size: 13))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(group.totalSize.formatted(.byteCount(style: .file)))
                        .font(Theme.caption)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(group.displayPath)

            if !isCollapsed {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 220), spacing: 10)],
                    spacing: 10
                ) {
                    ForEach(sortOrder.sorted(group.sessions)) { session in
                        SessionCard(
                            session: session,
                            isSelected: selection.ids.contains(session.id),
                            isDragged: drag?.sessions.contains(session) == true,
                            isShredding: shreddingIDs.contains(session.id) && !reduceMotion,
                            windowSpace: Self.windowSpace,
                            onClick: { click in
                                selection.click(session.id, click, in: orderedIDs)
                            },
                            onDragChanged: { dragChanged(session, to: $0) },
                            onDragEnded: dragEnded
                        )
                        .contextMenu {
                            Button("Show in Finder") { store.reveal(session) }
                            if session.isDeletable {
                                Button("Delete…") {
                                    if !selection.ids.contains(session.id) {
                                        selection.click(session.id, .plain, in: orderedIDs)
                                    }
                                    requestDelete()
                                }
                            }
                        }
                    }
                }
                .transition(.opacity)
            }
        }
    }

    // MARK: Detail

    /// One panel that changes shape: the session's details, then a place to drop
    /// it, then the confirmation, then the result.
    private var detailPanel: some View {
        let showsZone = drag != nil || deleteFlow != .idle

        return ZStack {
            if showsZone {
                DeleteZone(
                    isDragging: drag != nil,
                    isOverZone: drag?.isOverZone == true,
                    flow: deleteFlow,
                    onCancel: { withAnimation(Self.morph) { deleteFlow = .idle } },
                    onConfirm: delete
                )
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            } else {
                detail
                    .transition(.opacity)
            }
        }
        .frame(width: 372)
        .frame(maxHeight: .infinity)
        .background(panelBackground, in: RoundedRectangle(cornerRadius: Theme.panelRadius))
        .overlay {
            if drag != nil {
                RoundedRectangle(cornerRadius: Theme.panelRadius)
                    .strokeBorder(
                        drag?.isOverZone == true ? Theme.delete.opacity(0.6) : Color.primary.opacity(0.2),
                        style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])
                    )
            }
        }
        .scaleEffect(drag?.isOverZone == true ? 1.01 : 1)
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named(Self.windowSpace)) }) {
            detailFrame = $0
        }
    }

    private var panelBackground: Color {
        let isDanger: Bool
        switch deleteFlow {
        case .confirming, .deleting: isDanger = true
        default: isDanger = drag?.isOverZone == true
        }
        return isDanger ? Theme.delete.opacity(0.07) : Theme.card
    }

    @ViewBuilder
    private var detail: some View {
        switch selectedSessions.count {
        case 0:
            Text("Select a session")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case 1:
            SessionInspector(session: selectedSessions[0], store: store, onDelete: requestDelete)
                .id(selectedSessions[0].id)
        default:
            VStack(spacing: 4) {
                Text(totalSize(of: selectedSessions))
                    .font(Theme.number)
                Text(sessionCount(selectedSessions).lowercased())
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                if deletableSelection.count < selectedSessions.count {
                    Text("Sessions in use will be kept")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Button("Delete…", action: requestDelete)
                    .buttonStyle(DeleteButtonStyle())
                    .disabled(deletableSelection.isEmpty)
                    .padding(.top, 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// What the detail panel becomes while a session is on its way out.
private struct DeleteZone: View {
    let isDragging: Bool
    let isOverZone: Bool
    let flow: DeleteFlow
    let onCancel: () -> Void
    let onConfirm: ([Session]) -> Void

    /// The old content leaves before the new arrives, so two texts never overlap.
    private static var swap: AnyTransition {
        .asymmetric(
            insertion: .opacity.animation(.easeOut(duration: 0.16).delay(0.1)),
            removal: .opacity.animation(.easeIn(duration: 0.09))
        )
    }

    var body: some View {
        VStack(spacing: 14) {
            if case .finished = flow {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(.green)
                    .transition(Self.swap)
            } else {
                TrashCan(isOpen: isOverZone || isConfirming, color: canColor)
                    .transition(Self.swap)
            }
            message
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var isConfirming: Bool {
        if case .confirming = flow { true } else { false }
    }

    private var canColor: Color {
        switch flow {
        case .confirming, .deleting: Theme.delete
        default: isOverZone ? Theme.delete : Color.secondary
        }
    }

    @ViewBuilder
    private var message: some View {
        switch flow {
        case .idle:
            Text(isOverZone ? "Release to delete" : "Drop to delete")
                .font(.system(size: 13))
                .foregroundStyle(isOverZone ? Theme.delete : .secondary)
                .contentTransition(.opacity)
        case .confirming(let sessions):
            VStack(spacing: 6) {
                Text("Delete \(totalSize(of: sessions))?")
                    .font(Theme.number)
                Text(sessionCount(sessions).lowercased())
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text(deleteExplanation(for: sessions[0].source))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)

                HStack(spacing: 8) {
                    Button("Cancel", action: onCancel)
                        .buttonStyle(QuietButtonStyle())
                        .keyboardShortcut(.cancelAction)
                    Button("Delete") { onConfirm(sessions) }
                        .buttonStyle(DeleteButtonStyle())
                }
                .padding(.top, 10)
            }
            .transition(Self.swap)
        case .deleting:
            Text("Deleting…")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .transition(Self.swap)
        case .finished(let freed):
            Text("Freed \(freed)")
                .font(Theme.number)
                .transition(Self.swap)
        }
    }
}

/// The small tag that follows the pointer in place of the card.
private struct DragGhost: View {
    let sessions: [Session]
    let isOverZone: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(sessions.count == 1 ? sessions[0].title ?? "No Message" : sessionCount(sessions))
                .font(.system(size: 12.5))
                .lineLimit(1)
                .frame(maxWidth: 170, alignment: .leading)
            Text(totalSize(of: sessions))
                .font(Theme.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(Theme.sheet, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isOverZone ? Theme.delete.opacity(0.5) : Color.primary.opacity(0.1))
        }
        .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
        .rotationEffect(.degrees(isOverZone ? -2 : 0))
        .scaleEffect(isOverZone ? 0.92 : 1)
    }
}

// MARK: - Controls

/// The rounded outline shared by the chips above the list.
private struct ChipLabel: View {
    let title: String
    var showsMenuArrow = false
    var isSelected = false
    /// When set, the selected look slides between chips instead of switching.
    var namespace: Namespace.ID?

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
            if showsMenuArrow {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .medium))
            }
        }
        .font(.system(size: 12.5))
        .foregroundStyle(isSelected ? Theme.brand : .secondary)
        .padding(.horizontal, 14)
        .frame(height: 30)
        .background { outline }
        .contentShape(RoundedRectangle(cornerRadius: Theme.pillRadius))
    }
}

extension ChipLabel {
    @ViewBuilder
    fileprivate var outline: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.pillRadius)
        shape.strokeBorder(Color.primary.opacity(0.12))
        if isSelected {
            let selected = shape.fill(Theme.brand.opacity(0.08))
                .overlay { shape.strokeBorder(Theme.brand.opacity(0.32)) }
                .background(Theme.sheet, in: shape)
            if let namespace {
                selected.matchedGeometryEffect(id: "selected chip", in: namespace)
            } else {
                selected
            }
        }
    }
}

private struct Chip: View {
    let title: String
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ChipLabel(title: title, isSelected: isSelected, namespace: namespace)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct SortChip: View {
    @Binding var selection: SortOrder

    var body: some View {
        Menu {
            Picker("Sort By", selection: $selection) {
                ForEach(SortOrder.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            ChipLabel(title: selection.rawValue, showsMenuArrow: true)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

private struct SessionCard: View {
    let session: Session
    let isSelected: Bool
    let isDragged: Bool
    let isShredding: Bool
    let windowSpace: String
    let onClick: (ListSelection.Click) -> Void
    let onDragChanged: (CGPoint) -> Void
    let onDragEnded: () -> Void

    @State private var isHovered = false

    var body: some View {
        Group {
            if isShredding {
                Shredded { card }
            } else {
                card
            }
        }
        .opacity(isDragged ? 0.35 : 1)
        .scaleEffect(isDragged ? 0.97 : 1)
        .animation(.snappy(duration: 0.2), value: isDragged)
        .onHover { isHovered = $0 }
        .onTapGesture { onClick(Self.currentClick) }
        .gesture(
            DragGesture(minimumDistance: 6, coordinateSpace: .named(windowSpace))
                .onChanged { onDragChanged($0.location) }
                .onEnded { _ in onDragEnded() }
        )
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(session.title ?? "No Message")
                    .font(.system(size: 13))
                    .foregroundStyle(session.title == nil ? .secondary : .primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if !session.isDeletable {
                    Circle()
                        .fill(.green)
                        .frame(width: 7, height: 7)
                        .help("In use")
                        .accessibilityLabel("In use")
                }
            }

            HStack(alignment: .firstTextBaseline) {
                Text(session.size.formatted(.byteCount(style: .file)))
                    .font(Theme.number)
                Spacer(minLength: 8)
                Text(session.updatedAt, format: .relative(presentation: .named))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(14)
        .background(
            isSelected
                ? Theme.brand.opacity(0.08)
                : Color.primary.opacity(isHovered ? 0.07 : 0.04),
            in: RoundedRectangle(cornerRadius: Theme.cardRadius)
        )
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: Theme.cardRadius)
                    .strokeBorder(Theme.brand.opacity(0.32))
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
    }

    private static var currentClick: ListSelection.Click {
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) { return .toggle }
        if flags.contains(.shift) { return .extend }
        return .plain
    }
}

// MARK: - Detail

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
        VStack(alignment: .leading, spacing: 4) {
            Text(session.title ?? "No Message")
                .font(.system(size: 15, weight: .medium))
                .lineLimit(2)
            HStack(spacing: 4) {
                Text(session.updatedAt, format: .relative(presentation: .named))
                Text("·")
                Text(session.size.formatted(.byteCount(style: .file)))
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }

    @ViewBuilder
    private var transcript: some View {
        if let messages = detail?.messages, !messages.isEmpty {
            ScrollView {
                LazyVStack(spacing: 8) {
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
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            .scrollIndicators(.never)
        } else {
            // Stays blank while loading, which is too quick to be worth a label.
            Text(detail == nil ? "" : "No preview")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var files: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(detail?.files ?? []) { file in
                FileRow(file: file)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 12)
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
                        .frame(width: 7, height: 7)
                    Text("In use")
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            }
        }
        .padding(16)
    }
}

private struct MessageBubble: View {
    let message: TranscriptMessage

    private var isUser: Bool { message.role == .user }

    var body: some View {
        Text(message.text)
            .font(.system(size: 12.5))
            .lineSpacing(2)
            .textSelection(.enabled)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(
                isUser ? Theme.brand.opacity(0.12) : Theme.sheet,
                in: RoundedRectangle(cornerRadius: 12)
            )
            .frame(maxWidth: 290, alignment: isUser ? .trailing : .leading)
            .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }
}

private struct FileRow: View {
    let file: StoredFile

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(file.label)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text(file.size.formatted(.byteCount(style: .file)))
                    .font(Theme.caption)
                    .foregroundStyle(.secondary)
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
            .font(.system(size: 12.5))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .frame(height: 30)
            .overlay { RoundedRectangle(cornerRadius: Theme.pillRadius).strokeBorder(Color.primary.opacity(0.12)) }
            .contentShape(RoundedRectangle(cornerRadius: Theme.pillRadius))
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

private struct DeleteButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5))
            .foregroundStyle(Theme.delete)
            .padding(.horizontal, 14)
            .frame(height: 30)
            .background(Theme.delete.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.pillRadius))
            .overlay { RoundedRectangle(cornerRadius: Theme.pillRadius).strokeBorder(Theme.delete.opacity(0.28)) }
            .contentShape(RoundedRectangle(cornerRadius: Theme.pillRadius))
            .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.4)
    }
}

private func totalSize(of sessions: [Session]) -> String {
    sessions.reduce(0) { $0 + $1.size }.formatted(.byteCount(style: .file))
}
