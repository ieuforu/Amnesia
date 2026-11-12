import AmnesiaCore
import AppKit
import SwiftUI

struct LibraryWindowView: View {
    let store: SessionStore
    let undoManager: UndoManager
    let opening: LibraryOpening

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var library = SessionLibrary(demo: CommandLine.arguments.contains("--demo"))
    @State private var page = Page.library
    @State private var hasOpenedList = false
    @State private var storageScope: LibraryStorageScope?

    private enum Page: String, CaseIterable, Identifiable {
        case library = "Library"
        case list = "List"
        case storage = "Storage"

        var id: Self { self }

        var shortcut: KeyEquivalent {
            switch self {
            case .library: "1"
            case .list: "2"
            case .storage: "3"
            }
        }
    }

    var body: some View {
        let intro = reduceMotion ? nil : opening.sequence
        VStack(spacing: 0) {
            toolbar
            if page != .library { LibraryAppearance.rule.frame(height: 1) }

            ZStack {
                LibraryHomeView(store: store, library: library, undoManager: undoManager)
                    .opacity(page == .library ? 1 : 0)
                    .accessibilityHidden(page != .library)
                    .disabled(page != .library)
                    .allowsHitTesting(page == .library)
                if hasOpenedList {
                    SessionLibraryView(store: store, library: library, undoManager: undoManager, storageScope: $storageScope)
                        .opacity(page == .list ? 1 : 0)
                        .accessibilityHidden(page != .list)
                        .disabled(page != .list)
                        .allowsHitTesting(page == .list)
                }
                if page == .storage {
                    MainView(store: store) { group, source in
                        storageScope = LibraryStorageScope(title: group.displayName, path: group.projectPath, source: source)
                        show(.list)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .disabled(intro != nil)
        .accessibilityHidden(intro != nil)
        .overlay {
            if let intro {
                LibraryOpeningView { opening.dismiss(intro) }.id(intro)
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .background(LibraryAppearance.chrome)
        .foregroundStyle(LibraryAppearance.ink)
        .task {
            LibraryDropParticles.prewarm()
            LibraryOpeningParticles.prewarm()
            LibrarySessionMarks.prewarm()
            await store.refresh()
        }
        .onChange(of: opening.sequence, initial: true) { _, sequence in
            if reduceMotion, let sequence { opening.dismiss(sequence) }
        }
        .onChange(of: reduceMotion) { _, reducesMotion in
            if reducesMotion, let sequence = opening.sequence { opening.dismiss(sequence) }
        }
        .background {
            Button("Close Window") { NSApp.keyWindow?.performClose(nil) }
                .keyboardShortcut("w")
                .opacity(0)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 18) {
            if reduceMotion {
                brand
            } else {
                Button(action: opening.replay) { brand }
                    .buttonStyle(.plain)
                    .help("Replay opening animation")
                    .accessibilityLabel("Replay opening animation")
            }
            Spacer()

            HStack(spacing: 5) {
                ForEach(Page.allCases) { item in
                    Button { show(item) } label: {
                        Text(item.rawValue)
                            .font(.system(size: 12, weight: page == item ? .semibold : .medium))
                            .padding(.horizontal, 9)
                            .frame(height: 26)
                            .foregroundStyle(page == item ? LibraryAppearance.ink : LibraryAppearance.muted)
                            .background(page == item ? LibraryAppearance.chrome : .clear, in: RoundedRectangle(cornerRadius: 5))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(page == item ? .isSelected : [])
                    .keyboardShortcut(item.shortcut)
                }
            }
            Button {
                Task { await store.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(LibraryAppearance.muted)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Refresh sessions")
            .accessibilityLabel("Refresh sessions")
            .disabled(store.isBusy)
        }
        .padding(.leading, 86)
        .padding(.trailing, 17)
        .frame(height: 46)
        .background(page == .library ? LibraryAppearance.paper : LibraryAppearance.index)
    }

    private var brand: some View {
        HStack(spacing: 7) {
            LibraryDotMark().frame(width: 15, height: 15)
            Text("Amnesia").font(.system(size: 13, weight: .semibold)).tracking(-0.2)
        }
    }

    private func show(_ next: Page) {
        if next == .list { hasOpenedList = true }
        page = next
    }
}

private struct LibraryStorageScope: Equatable {
    let title: String
    let path: String?
    let source: SessionSource
}

private struct SessionLibraryView: View {
    let store: SessionStore
    @Bindable var library: SessionLibrary
    let undoManager: UndoManager
    @Binding var storageScope: LibraryStorageScope?

    @FocusState private var searchFocused: Bool
    @FocusState private var collectionNameFocused: Bool
    @State private var collectionID: UUID?
    @State private var sourceFilter: SessionSource?
    @State private var selection: Set<SessionReference> = []
    @State private var query = ""
    @State private var newName = ""
    @State private var creatingCollection = false
    @State private var collectionError: String?
    @State private var openingTerminal = false
    @State private var actionError: String?
    @State private var showingOrganize = false
    @State private var receipt: MembershipReceipt?
    @State private var pulse: DropPulse?

    private struct MembershipReceipt: Identifiable {
        let id = UUID()
        let text: String
    }

    private struct DropPulse: Identifiable {
        let id = UUID()
        let collection: UUID
        let claudeCount: Int
        let codexCount: Int
    }

    private var collection: SessionCollection? {
        library.contents.collections.first { $0.id == collectionID }
    }

    private var visible: [Session] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let members = collection?.members
        return store.librarySessions.filter { session in
            if let members, !members.contains(SessionReference(session)) { return false }
            if let sourceFilter, session.source != sourceFilter { return false }
            if let storageScope, (session.source != storageScope.source || session.projectPath != storageScope.path) {
                return false
            }
            guard !query.isEmpty else { return true }
            return [session.title, session.firstMessage, session.latestUserMessage, session.projectPath, session.source.displayName]
                .compactMap { $0 }
                .contains { $0.localizedStandardContains(query) }
        }
    }

    var body: some View {
        let visible = visible
        HSplitView {
            sidebar
                .frame(minWidth: 152, idealWidth: 176, maxWidth: 200, maxHeight: .infinity)
            sessionList(visible)
                .frame(minWidth: 320, idealWidth: 440, maxWidth: .infinity, maxHeight: .infinity)
            ZStack { preview(visible) }
                .frame(minWidth: 290, idealWidth: 420, maxWidth: 520, maxHeight: .infinity)
        }
        .onChange(of: visible.map(SessionReference.init), initial: true) { _, references in
            selection.formIntersection(references)
            if selection.isEmpty, let first = references.first { selection.insert(first) }
        }
        .onChange(of: storageScope) { _, scope in
            if scope != nil {
                collectionID = nil
                sourceFilter = nil
                query = ""
            }
        }
        .task(id: receipt?.id) {
            guard receipt != nil else { return }
            try? await Task.sleep(for: .seconds(5))
            if !Task.isCancelled { receipt = nil }
        }
        .task(id: pulse?.id) {
            guard pulse != nil else { return }
            try? await Task.sleep(for: .milliseconds(620))
            if !Task.isCancelled { pulse = nil }
        }
        .background {
            Button("Undo Collection Change", action: undoLastChange)
                .keyboardShortcut("z")
                .opacity(0)
            Button("Redo Collection Change") { undoManager.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .opacity(0)
        }
        .alert("Amnesia", isPresented: Binding(
            get: { actionError != nil || library.error != nil },
            set: { if !$0 { actionError = nil; library.error = nil } }
        )) {
            Button("OK") { actionError = nil; library.error = nil }
        } message: {
            Text(actionError ?? library.error ?? "")
        }
    }

    private var sidebar: some View {
        let sourceCounts = store.librarySessions.reduce(into: [SessionSource: Int]()) { counts, session in
            counts[session.source, default: 0] += 1
        }
        return VStack(alignment: .leading, spacing: 4) {
            Button { showCollection(nil) } label: {
                LibrarySidebarLabel(title: "Recent", icon: "clock",
                                    selected: collectionID == nil && storageScope == nil && sourceFilter == nil)
            }
            .buttonStyle(.plain)

            Text("Sources")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(LibraryAppearance.muted)
                .padding(.leading, 9)
                .padding(.top, 12)
                .padding(.bottom, 2)
            ForEach(SessionSource.allCases) { source in
                Button { showSource(source) } label: {
                    LibrarySidebarLabel(
                        title: source.displayName, icon: "circle.fill", selected: sourceFilter == source,
                        count: sourceCounts[source, default: 0],
                        iconTint: source == .claudeCode ? LibraryAppearance.claude : LibraryAppearance.accent
                    )
                }
                .buttonStyle(.plain)
            }

            HStack {
                Text("Collections")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(LibraryAppearance.muted)
                Spacer()
                if creatingCollection || !library.contents.collections.isEmpty {
                    Button(action: toggleCollectionEditor) {
                        Image(systemName: creatingCollection ? "xmark" : "plus").frame(width: 10)
                    }
                    .buttonStyle(LibraryButtonStyle())
                    .accessibilityLabel(creatingCollection ? "Cancel New Collection" : "New Collection")
                    .help(creatingCollection ? "Cancel" : "New Collection")
                    .disabled(!library.canEdit)
                }
            }
            .padding(.leading, 9)
            .padding(.top, 17)
            .padding(.bottom, 3)

            if creatingCollection { collectionEditor }

            if library.contents.collections.isEmpty && !creatingCollection {
                Button(action: toggleCollectionEditor) {
                    LibrarySidebarLabel(title: "New collection", icon: "plus", selected: false,
                                        iconTint: LibraryAppearance.accent)
                }
                .buttonStyle(.plain)
                .disabled(!library.canEdit)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(library.contents.collections) { item in
                        LibraryCollectionRow(item: item, selected: collectionID == item.id, canDrop: library.canEdit) {
                            showCollection(item.id)
                        } onDrop: { sessions in
                            setMembership(sessions, in: item.id, to: true, animateDrop: true)
                        }
                        .frame(height: 34)
                        .overlay(alignment: .leading) {
                            if let pulse, pulse.collection == item.id {
                                LibraryDropParticles(claudeCount: pulse.claudeCount, codexCount: pulse.codexCount)
                                    .frame(width: 112, height: 38)
                                    .id(pulse.id)
                                    .allowsHitTesting(false)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                }
            }
            .defaultScrollAnchor(.top)
        }
        .padding(.horizontal, 13)
        .padding(.top, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(LibraryAppearance.chrome)
    }

    private var collectionEditor: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                TextField("Collection name", text: $newName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($collectionNameFocused)
                    .onSubmit(createCollection)
                    .accessibilityLabel("Collection name")
                Button(action: createCollection) { Image(systemName: "checkmark") }
                    .buttonStyle(.plain)
                    .foregroundStyle(LibraryAppearance.accent)
                    .accessibilityLabel("Create Collection")
                    .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 8)
            .frame(height: 32)
            .background(LibraryAppearance.index, in: RoundedRectangle(cornerRadius: 6))
            .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(LibraryAppearance.accent) }

            if let collectionError {
                Text(collectionError)
                    .font(.system(size: 10))
                    .foregroundStyle(LibraryAppearance.muted)
            }
        }
        .padding(.bottom, 5)
        .onAppear { collectionNameFocused = true }
        .onExitCommand { creatingCollection = false }
    }

    private func sessionList(_ sessions: [Session]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 9) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(storageScope?.title ?? collection?.name ?? sourceFilter?.displayName ?? "Recent sessions")
                        .font(.system(size: 21, weight: .semibold))
                        .tracking(-0.45)
                        .lineLimit(1)
                        .accessibilityAddTraits(.isHeader)
                    HStack(spacing: 6) {
                        Text(sessions.count == 1 ? "1 session" : "\(sessions.count) sessions")
                            .monospacedDigit()
                        if let storageScope {
                            Text("· \(storageScope.source.displayName)")
                            Button { showCollection(nil) } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.plain)
                                .help("Clear storage filter")
                                .accessibilityLabel("Clear storage filter")
                        }
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(LibraryAppearance.muted)
                }
                Spacer()
                if !library.contents.collections.isEmpty { collectionActions }
            }
            .padding(.horizontal, 20)
            .padding(.top, 15)
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").foregroundStyle(LibraryAppearance.muted)
                TextField("Find a session…", text: $query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .accessibilityIdentifier("library-search")
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(LibraryAppearance.muted)
                        .accessibilityLabel("Clear Search")
                } else {
                    Text("⌘F")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(LibraryAppearance.muted)
                        .accessibilityHidden(true)
                }
            }
            .font(.system(size: 12))
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(LibraryAppearance.paper, in: RoundedRectangle(cornerRadius: 7))
            .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(searchFocused ? LibraryAppearance.accent : LibraryAppearance.rule) }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 11)
            LibraryAppearance.rule.frame(height: 1)

            if sessions.isEmpty {
                if store.isBusy {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    LibraryEmptyState(
                        title: query.isEmpty ? "No sessions here yet" : "No matching sessions",
                        detail: query.isEmpty && collectionID != nil ? "Drag sessions here from Recent." : nil,
                        icon: query.isEmpty ? "tray" : "magnifyingglass"
                    )
                }
            } else {
                SessionLibraryTable(sessions: sessions, selection: $selection)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(LibraryAppearance.index)
        .overlay(alignment: .bottom) {
            if let receipt {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(LibraryAppearance.accent)
                    Text(receipt.text).lineLimit(1)
                    Button("Undo", action: undoLastChange)
                        .buttonStyle(LibraryButtonStyle())
                }
                .font(.system(size: 12, weight: .medium))
                .padding(.vertical, 6)
                .padding(.leading, 12)
                .padding(.trailing, 6)
                .background(LibraryAppearance.paper, in: RoundedRectangle(cornerRadius: 9))
                .overlay { RoundedRectangle(cornerRadius: 9).strokeBorder(LibraryAppearance.rule) }
                .shadow(color: .black.opacity(0.09), radius: 7, y: 3)
                .padding(12)
            }
        }
        .background {
            Button("Find Sessions") { searchFocused = true }
                .keyboardShortcut("f")
                .opacity(0)
        }
    }

    private var collectionActions: some View {
        Button { showingOrganize.toggle() } label: {
            Label("Organize", systemImage: "folder.badge.plus")
        }
        .buttonStyle(LibraryButtonStyle())
        .fixedSize()
        .help("Add selected sessions to a collection")
        .disabled(selection.isEmpty || library.contents.collections.isEmpty || !library.canEdit)
        .popover(isPresented: $showingOrganize, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Add to collection")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(LibraryAppearance.muted)
                    .padding(.horizontal, 9)
                    .padding(.bottom, 5)
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(library.contents.collections) { item in
                            Button {
                                setMembership(selection, in: item.id, to: true)
                                showingOrganize = false
                            } label: {
                                LibrarySidebarLabel(title: item.name, icon: "folder", selected: false)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: min(CGFloat(library.contents.collections.count) * 36, 240))
                if let collectionID {
                    LibraryAppearance.rule.frame(height: 1)
                    Button {
                        setMembership(selection, in: collectionID, to: false)
                        showingOrganize = false
                    } label: {
                        LibrarySidebarLabel(title: "Remove from this collection", icon: "folder.badge.minus", selected: false)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(width: 205)
            .padding(8)
            .background(LibraryAppearance.paper)
        }
    }

    @ViewBuilder
    private func preview(_ sessions: [Session]) -> some View {
        if selection.count > 1 {
            LibraryEmptyState(
                title: "\(selection.count) sessions selected",
                detail: "Drag them into a collection to keep them together.",
                icon: "rectangle.on.rectangle"
            )
            .background(LibraryAppearance.paper)
        } else if let session = sessions.first(where: { selection.contains(SessionReference($0)) }) {
            LibraryReader(session: session, store: store) {
                if !CommandLine.arguments.contains("--demo"), let resume = SessionResume(session) {
                    Button { resumeSession(resume) } label: {
                        Label("Continue in Ghostty", systemImage: "arrow.up.right")
                    }
                    .buttonStyle(LibraryButtonStyle(prominent: true))
                    .disabled(openingTerminal || session.isActive)

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(resume.command, forType: .string)
                    } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(LibraryButtonStyle())
                    .help("Copy Resume Command")
                    .accessibilityLabel("Copy Resume Command")
                    .disabled(session.isActive)
                }
            }
            .id(SessionReference(session))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            LibraryEmptyState(title: "Select a session", detail: nil, icon: "text.alignleft")
                .background(LibraryAppearance.paper)
        }
    }

    private func showCollection(_ id: UUID?) {
        storageScope = nil
        sourceFilter = nil
        collectionID = id
        query = ""
        selection = Set(visible.prefix(1).map(SessionReference.init))
    }

    private func showSource(_ source: SessionSource) {
        storageScope = nil
        collectionID = nil
        sourceFilter = source
        selection = Set(visible.prefix(1).map(SessionReference.init))
    }

    private func toggleCollectionEditor() {
        newName = ""
        collectionError = nil
        creatingCollection.toggle()
    }

    private func createCollection() {
        do {
            // Stay in the source list so it is ready for the first drop.
            _ = try library.create(newName)
            creatingCollection = false
            collectionError = nil
        } catch {
            collectionError = error.localizedDescription
        }
    }

    @discardableResult
    private func setMembership(_ sessions: Set<SessionReference>, in id: UUID, to member: Bool, animateDrop: Bool = false) -> Bool {
        let knownSessions = Set(store.librarySessions.map(SessionReference.init))
        let changed = library.setMembership(of: sessions.intersection(knownSessions), in: id, to: member, undo: undoManager)
        guard !changed.isEmpty, let name = library.contents.collections.first(where: { $0.id == id })?.name else { return false }

        let count = changed.count == 1 ? "1 session" : "\(changed.count) sessions"
        let text = member ? "Added \(count) to \(name)" : "Removed \(count) from \(name)"
        receipt = MembershipReceipt(text: text)
        if animateDrop {
            let claudeCount = changed.filter { $0.source == .claudeCode }.count
            pulse = DropPulse(collection: id, claudeCount: claudeCount, codexCount: changed.count - claudeCount)
        }
        return true
    }

    private func undoLastChange() {
        undoManager.undo()
        receipt = nil
        pulse = nil
    }

    private func resumeSession(_ resume: SessionResume) {
        openingTerminal = true
        Task {
            defer { openingTerminal = false }
            do { try await resume.openInGhostty() }
            catch { actionError = error.localizedDescription }
        }
    }
}

private struct LibraryEmptyState: View {
    let title: String
    let detail: String?
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(LibraryAppearance.accent)
                .frame(width: 36, height: 36)
                .background(LibraryAppearance.selection, in: RoundedRectangle(cornerRadius: 9))
                .accessibilityHidden(true)
            Text(title).font(.system(size: 16, weight: .semibold))
            if let detail {
                Text(detail).font(.system(size: 12)).foregroundStyle(LibraryAppearance.muted)
            }
        }
        .padding(.top, 29)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct LibrarySidebarLabel: View {
    let title: String
    let icon: String
    let selected: Bool
    var count: Int? = nil
    var iconTint: Color? = nil
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: icon == "circle.fill" ? 6 : 12, weight: .medium))
                .foregroundStyle(iconTint ?? (selected ? LibraryAppearance.accent : LibraryAppearance.muted))
                .frame(width: 15)
                .accessibilityHidden(true)
            Text(title).lineLimit(1)
            Spacer(minLength: 0)
            if let count, count > 0 {
                Text(count.formatted())
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(LibraryAppearance.muted)
            }
        }
        .font(.system(size: 12, weight: selected ? .semibold : .medium))
        .foregroundStyle(selected ? LibraryAppearance.accent : LibraryAppearance.ink)
        .padding(.horizontal, 9)
        .frame(maxWidth: .infinity, minHeight: 29, alignment: .leading)
        .background(selected ? LibraryAppearance.selection : hovered ? LibraryAppearance.index : .clear,
                    in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct LibraryCollectionRow: NSViewRepresentable {
    let item: SessionCollection
    let selected: Bool
    let canDrop: Bool
    let onSelect: () -> Void
    let onDrop: (Set<SessionReference>) -> Bool

    func makeNSView(context: Context) -> DropView {
        let view = DropView(rootView: label(targeted: false))
        view.registerForDraggedTypes([SessionLibraryDrag.pasteboardType])
        return view
    }

    func updateNSView(_ view: DropView, context: Context) {
        view.canDrop = canDrop
        view.onDrop = onDrop
        view.render = { [self] targeted in label(targeted: targeted) }
        view.rootView = label(targeted: view.targeted)
    }

    private func label(targeted: Bool) -> DropLabel {
        DropLabel(title: item.name, count: item.members.count, selected: selected, targeted: targeted, onSelect: onSelect)
    }

    final class DropView: NSHostingView<DropLabel> {
        var canDrop = false
        var onDrop: ((Set<SessionReference>) -> Bool)?
        var render: ((Bool) -> DropLabel)?
        private(set) var targeted = false

        override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
            updateTarget(sender)
        }

        override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
            updateTarget(sender)
        }

        override func draggingExited(_ sender: (any NSDraggingInfo)?) { setTargeted(false) }

        override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
            defer { setTargeted(false) }
            guard canDrop else { return false }
            let sessions = SessionLibraryDrag.references(from: sender.draggingPasteboard)
            guard !sessions.isEmpty else { return false }
            return onDrop?(sessions) ?? false
        }

        private func updateTarget(_ sender: any NSDraggingInfo) -> NSDragOperation {
            let valid = canDrop && sender.draggingPasteboard.types?.contains(SessionLibraryDrag.pasteboardType) == true
            setTargeted(valid)
            return valid ? .copy : []
        }

        private func setTargeted(_ active: Bool) {
            guard targeted != active else { return }
            targeted = active
            if let render { rootView = render(active) }
        }
    }

    struct DropLabel: View {
        let title: String
        let count: Int
        let selected: Bool
        let targeted: Bool
        let onSelect: () -> Void

        var body: some View {
            Button(action: onSelect) {
                LibrarySidebarLabel(title: title, icon: "folder", selected: selected || targeted, count: count)
            }
            .buttonStyle(.plain)
            .overlay {
                if targeted {
                    RoundedRectangle(cornerRadius: 6).strokeBorder(LibraryAppearance.accent, lineWidth: 1)
                        .allowsHitTesting(false)
                }
            }
        }
    }
}
