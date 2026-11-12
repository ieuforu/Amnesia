import AmnesiaCore
import AppKit
import SwiftUI

/// A browseable index of launch directories, with collection targets always in reach.
struct LibraryHomeView: View {
    let store: SessionStore
    let library: SessionLibrary
    let undoManager: UndoManager

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var searchFocused: Bool
    @FocusState private var collectionNameFocused: Bool
    @State private var query = ""
    @State private var collectionID: UUID?
    @State private var directoryID: String?
    @State private var reading: Reading?
    @State private var latestSource = CGRect.null
    @State private var newCollection: String?
    @State private var error: String?
    @State private var receipt: LibraryHomeDropReceipt?
    @State private var openingTerminal = false

    private struct Reading {
        let session: Session
        let source: CGRect?
    }

    private var collection: SessionCollection? {
        library.contents.collections.first { $0.id == collectionID }
    }

    var body: some View {
        let all = store.librarySessions
        let members = collection?.members
        let scope = members.map { refs in all.filter { refs.contains(SessionReference($0)) } } ?? all
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matching = term.isEmpty ? scope : scope.filter { session in
            [session.title, session.latestUserMessage, session.projectPath, session.source.displayName]
                .compactMap { $0 }.contains { $0.localizedStandardContains(term) }
        }
        let groups = LibraryLaunchGroup.make(from: scope)
        let directory = groups.first { $0.id == directoryID }
        let matches = directory.map { group in matching.filter { $0.projectPath == group.path } } ?? matching
        let showingReel = directory == nil && collection == nil && term.isEmpty

        VStack(alignment: .leading, spacing: 0) {
            heading(sessions: all, directories: groups.count)
                .padding(.bottom, 19)
            LibraryHomeCollections(collections: library.contents.collections, selectedID: collectionID,
                                   onSelect: showCollection, onDrop: add, onNew: toggleCollection, receipt: receipt)
                .padding(.bottom, 12)
            if newCollection != nil {
                collectionEditor.frame(width: 315).padding(.bottom, 12)
            }

            if showingReel {
                if groups.isEmpty {
                    empty(store.isBusy ? "Looking for local sessions…" : "No local sessions found")
                } else {
                    LibrarySessionReel(groups: groups, collections: library.canEdit ? library.contents.collections : [],
                                       onDirectory: { directoryID = $0.id }, onOpen: openReader,
                                       onCollect: { _ = add([$0], to: $1) })
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let directory {
                            directoryHeading(directory, count: matches.count)
                            sessionRows(matches, showPath: false)
                        } else if let collection {
                            sectionHeader(collection.name, detail: sessionCount(matches.count))
                            sessionRows(matches, showPath: true)
                        } else {
                            sectionHeader("Search results", detail: sessionCount(matches.count))
                            sessionRows(matches, showPath: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 12)
                    .padding(.bottom, 26)
                }
                .id(directoryID ?? collectionID?.uuidString ?? "search")
            }
        }
        .padding(.horizontal, 30)
        .padding(.top, 21)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(LibraryAppearance.paper)
        .allowsHitTesting(reading == nil)
        .accessibilityHidden(reading != nil)
        .overlay {
            if let reading {
                let reference = SessionReference(reading.session)
                reader(all.first { SessionReference($0) == reference } ?? reading.session)
                    .transition(.readerMorph(from: reading.source))
                    .zIndex(1)
            }
        }
        .coordinateSpace(name: LibraryReaderCoordinates.name)
        .background {
            Button("Find Sessions") { if reading == nil { searchFocused = true } }
                .keyboardShortcut("f")
                .opacity(0)
            Button("Undo Collection Change") { undoManager.undo(); receipt = nil }
                .keyboardShortcut("z")
                .opacity(0)
            Button("Redo Collection Change") { undoManager.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .opacity(0)
        }
        .onExitCommand {
            if reading != nil { closeReader() }
            else if newCollection != nil { newCollection = nil }
            else if !query.isEmpty { query = "" }
            else if directoryID != nil { closeDirectory() }
            else { collectionID = nil }
        }
        .task(id: receipt?.id) {
            guard receipt != nil else { return }
            try? await Task.sleep(for: .milliseconds(620))
            if !Task.isCancelled { receipt = nil }
        }
        .alert("Amnesia", isPresented: Binding(
            get: { error != nil || library.error != nil },
            set: { if !$0 { error = nil; library.error = nil } }
        )) {
            Button("OK") { error = nil; library.error = nil }
        } message: { Text(error ?? library.error ?? "") }
    }

    private func heading(sessions: [Session], directories: Int) -> some View {
        HStack(alignment: .bottom, spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Sessions")
                    .font(.system(size: 35, weight: .semibold)).tracking(-1.7)
                    .accessibilityAddTraits(.isHeader)
                Text("\(sessionCount(sessions.count)) across \(directories) launch directories")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(LibraryAppearance.muted)
            }
            Spacer(minLength: 12)
            if let latest = sessions.first {
                Button { openReader(latest, latestSource) } label: {
                    Label("Open latest", systemImage: "arrow.up.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(LibraryAppearance.accent)
                        .frame(height: 30)
                }
                .buttonStyle(.plain)
                .help(displayTitle(latest))
                .measureReaderSource { latestSource = $0 }
            }
            search.frame(width: 230)
        }
    }

    private var search: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").accessibilityHidden(true)
            TextField("Find a session or path", text: $query)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .foregroundStyle(LibraryAppearance.ink)
                .accessibilityIdentifier("home-search")
            if query.isEmpty {
                Text("⌘F").font(.system(size: 10, design: .monospaced)).accessibilityHidden(true)
            } else {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).accessibilityLabel("Clear Search")
            }
        }
        .foregroundStyle(LibraryAppearance.muted)
        .font(.system(size: 12))
        .padding(.horizontal, 9)
        .frame(height: 30)
        .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(searchFocused ? LibraryAppearance.accent : LibraryAppearance.rule).allowsHitTesting(false) }
    }

    private var collectionEditor: some View {
        HStack(spacing: 8) {
            TextField("Collection name", text: Binding(get: { newCollection ?? "" }, set: { newCollection = $0 }))
                .textFieldStyle(.plain)
                .focused($collectionNameFocused)
                .padding(.horizontal, 10)
                .frame(minWidth: 76, maxWidth: .infinity, minHeight: 28)
                .background(LibraryAppearance.index, in: RoundedRectangle(cornerRadius: 6))
                .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(LibraryAppearance.rule).allowsHitTesting(false) }
                .onSubmit(createCollection)
            Button("Create", action: createCollection).buttonStyle(LibraryButtonStyle(prominent: true))
            Button("Cancel") { newCollection = nil }.buttonStyle(.plain)
        }
        .font(.system(size: 12))
        .onAppear { collectionNameFocused = true }
    }

    private func sectionHeader(_ title: String, detail: String) -> some View {
        HStack(spacing: 8) {
            Text(verbatim: title).font(.system(size: 14, weight: .semibold)).accessibilityAddTraits(.isHeader)
            if !detail.isEmpty { Text(detail).font(.system(size: 11)).monospacedDigit().foregroundStyle(LibraryAppearance.muted) }
        }
    }

    private func directoryHeading(_ group: LibraryLaunchGroup, count: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: closeDirectory) {
                Label("Sessions", systemImage: "chevron.left").font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(LibraryAppearance.muted)
            sectionHeader(group.title, detail: sessionCount(count))
            Text(verbatim: pathLabel(group.path))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(LibraryAppearance.muted)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder private func sessionRows(_ sessions: [Session], showPath: Bool) -> some View {
        if sessions.isEmpty {
            empty(query.isEmpty ? "Drag a session onto the collection’s name above." : "No matching sessions")
        } else {
            LazyVStack(spacing: 0) {
                ForEach(sessions, id: \.fileURL) { session in
                    LibraryHomeSessionRow(session: session, showPath: showPath) { openReader(session, $0) }
                        .contextMenu {
                            if !library.contents.collections.isEmpty && library.canEdit {
                                Menu("Add to Collection") {
                                    ForEach(library.contents.collections) { item in
                                        Button(item.name) { _ = add([SessionReference(session)], to: item.id) }
                                            .disabled(item.members.contains(SessionReference(session)))
                                    }
                                }
                                if let collectionID {
                                    Button("Remove from Collection") {
                                        library.setMembership(of: [SessionReference(session)], in: collectionID, to: false, undo: undoManager)
                                    }
                                }
                            }
                        }
                    if session.fileURL != sessions.last?.fileURL {
                        LibraryAppearance.rule.frame(height: 1).padding(.horizontal, 12)
                    }
                }
            }
            .overlay(alignment: .top) { LibraryAppearance.rule.frame(height: 1).allowsHitTesting(false) }
        }
    }

    private func empty(_ text: String) -> some View {
        Text(text).font(.system(size: 12)).foregroundStyle(LibraryAppearance.muted)
            .padding(.vertical, 23).frame(maxWidth: .infinity, alignment: .leading)
    }

    private func reader(_ session: Session) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: closeReader) {
                    Label("Back to sessions", systemImage: "chevron.left")
                        .font(.system(size: 12, weight: .medium))
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut("[", modifiers: [.command])
                Spacer()
            }
            .foregroundStyle(LibraryAppearance.accent)
            .padding(.horizontal, 20)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .padding(.top, 7)

            LibraryReader(session: session, store: store, columnWidth: 760) {
                if !CommandLine.arguments.contains("--demo"), let resume = SessionResume(session) {
                    Button { resumeSession(resume) } label: { Label("Continue in Ghostty", systemImage: "arrow.up.right") }
                        .buttonStyle(LibraryButtonStyle(prominent: true))
                        .disabled(openingTerminal || session.isActive)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(resume.command, forType: .string)
                    } label: { Image(systemName: "doc.on.doc") }
                        .buttonStyle(LibraryButtonStyle())
                        .accessibilityLabel("Copy Resume Command")
                        .disabled(session.isActive)
                }
            }
            .id(SessionReference(session))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LibraryAppearance.index)
    }

    private func openReader(_ session: Session, _ source: CGRect?) {
        guard reading == nil else { return }
        searchFocused = false
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.29)) {
            reading = Reading(session: session, source: source)
        }
    }

    private func closeReader() {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { reading = nil }
    }

    private func showCollection(_ id: UUID?) {
        closeDirectory()
        collectionID = id
        query = ""
    }

    private func closeDirectory() {
        directoryID = nil
    }

    private func toggleCollection() {
        guard library.canEdit else { return }
        newCollection = newCollection == nil ? "" : nil
    }

    private func createCollection() {
        guard let newCollection, !newCollection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        do { _ = try library.create(newCollection); self.newCollection = nil }
        catch { self.error = error.localizedDescription }
    }

    private func add(_ references: [SessionReference], to id: UUID) -> Bool {
        let known = Set(store.librarySessions.map(SessionReference.init))
        let changed = library.setMembership(of: Set(references).intersection(known), in: id, to: true, undo: undoManager)
        guard !changed.isEmpty else { return false }
        let claude = changed.lazy.filter { $0.source == .claudeCode }.count
        receipt = LibraryHomeDropReceipt(collectionID: id, claude: claude, codex: changed.count - claude)
        return true
    }

    private func resumeSession(_ resume: SessionResume) {
        openingTerminal = true
        Task {
            defer { openingTerminal = false }
            do { try await resume.openInGhostty() }
            catch { self.error = error.localizedDescription }
        }
    }
}

private struct LibraryHomeSessionRow: View {
    let session: Session
    let showPath: Bool
    var inset: CGFloat = 13
    let onOpen: (CGRect) -> Void
    @State private var hovered = false
    @State private var source = CGRect.null

    var body: some View {
        let title = displayTitle(session)
        Button { onOpen(source) } label: {
            HStack(spacing: 8) {
                Circle().fill(sourceTint(session.source)).frame(width: 5, height: 5)
                    .accessibilityLabel(session.source.displayName)
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    if showPath, let path = session.projectPath {
                        Text(verbatim: pathLabel(path)).font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(LibraryAppearance.muted).lineLimit(1).truncationMode(.middle)
                    }
                }
                Spacer(minLength: 4)
                Text(session.updatedAt, format: .dateTime.month(.abbreviated).day())
                    .font(.system(size: 10)).monospacedDigit().foregroundStyle(LibraryAppearance.muted).fixedSize()
            }
            .padding(.horizontal, inset)
            .frame(height: showPath ? 45 : 37)
            .contentShape(Rectangle())
            .background(hovered ? LibraryAppearance.chrome.opacity(0.55) : .clear)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .measureReaderSource { source = $0 }
        .draggable(SessionReference(session)) {
            Text(verbatim: title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                .frame(maxWidth: 215).padding(.horizontal, 11).padding(.vertical, 7)
                .background(LibraryAppearance.index, in: RoundedRectangle(cornerRadius: 7))
        }
    }
}

func pathLabel(_ path: String?) -> String {
    path.map { ($0 as NSString).abbreviatingWithTildeInPath } ?? "Launch path not recorded"
}

private func sessionCount(_ count: Int) -> String { count == 1 ? "1 session" : "\(count) sessions" }

func sourceTint(_ source: SessionSource) -> Color {
    source == .claudeCode ? LibraryAppearance.claude : LibraryAppearance.accent
}

func displayTitle(_ session: Session) -> String {
    guard let title = session.title else { return "Untitled session" }
    guard title.contains("<image name=[") else { return title }
    let text = title.replacingOccurrences(of: #"<image name=\[[^\]]+\] path="[^"]*(?:"\s*/?>|$)"#, with: "", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return text.isEmpty ? "Image attachment" : text
}
