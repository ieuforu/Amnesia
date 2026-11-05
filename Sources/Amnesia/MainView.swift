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
    /// Validated as a pair for color blindness. Each agent keeps its color.
    static let claude = Color(red: 0.77, green: 0.33, blue: 0.16)
    static let codex = Color(red: 0.32, green: 0.30, blue: 0.84)
    static let tileRadius: CGFloat = 14
    static let panelRadius: CGFloat = 18
    /// Just under half the 30pt height: outlining fully rounded ends leaves
    /// small spikes where the two arcs meet.
    static let pillRadius: CGFloat = 13

    static func color(for source: SessionSource) -> Color {
        source == .claudeCode ? claude : codex
    }
    static let number = Font.system(size: 22, weight: .regular, design: .monospaced)
    static let hero = Font.system(size: 46, weight: .light, design: .monospaced)
    static let caption = Font.system(size: 12, design: .monospaced)
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

/// A project on the map. One folder can hold sessions from both agents.
private struct Region: Identifiable, Equatable {
    let source: SessionSource
    let group: SessionGroup

    var id: String { "\(source.rawValue)|\(group.id)" }
}

/// A map of what's stored. Area is size, and a tile dissolves into dots the
/// longer it goes unused, so it shows both what takes the most space and what
/// has already been forgotten. Clicking zooms in a level.
struct MainView: View {
    let store: SessionStore

    @State private var focusedRegionID: String?
    @State private var selectedID: String?
    @State private var deleteFlow = DeleteFlow.idle
    @State private var drag: CardDrag?
    @State private var detailFrame = CGRect.zero
    @State private var hasAppeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let windowSpace = "window"
    private static let morph = Animation.snappy(duration: 0.42)
    private static let panelWidth: CGFloat = 400

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            summary
            HStack(spacing: 12) {
                map
                if showsPanel {
                    detailPanel
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .ignoresSafeArea(.container, edges: .top)
        .background(Theme.sheet)
        .task {
            await store.refresh()
            withAnimation(reduceMotion ? nil : .easeOut(duration: 1.1)) { hasAppeared = true }
        }
        .onChange(of: store.sessions) {
            if let selectedID, !store.sessions.contains(where: { $0.id == selectedID }) {
                self.selectedID = nil
            }
            if let focusedRegionID, !regions.contains(where: { $0.id == focusedRegionID }) {
                self.focusedRegionID = nil
            }
        }
        .background {
            // This window has no File menu to provide the shortcut.
            Button("Close Window") { NSApp.keyWindow?.performClose(nil) }
                .keyboardShortcut("w")
                .opacity(0)
            Button("Back", action: goBack)
                .keyboardShortcut(.cancelAction)
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

    // MARK: Data

    private var regions: [Region] {
        SessionSource.allCases.flatMap { source in
            SessionGroup.grouping(store.sessions.filter { $0.source == source })
                .map { Region(source: source, group: $0) }
        }
    }

    private var focusedRegion: Region? {
        regions.first { $0.id == focusedRegionID }
    }

    private var selectedSession: Session? {
        store.sessions.first { $0.id == selectedID }
    }

    private var showsPanel: Bool {
        selectedSession != nil || drag != nil || deleteFlow != .idle
    }

    private var shreddingIDs: Set<String> {
        if case .deleting(let sessions) = deleteFlow { Set(sessions.map(\.id)) } else { [] }
    }

    // MARK: Summary

    private var scopeSessions: [Session] {
        focusedRegion?.group.sessions ?? store.sessions
    }

    private var summary: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Button(action: goBack) {
                    HStack(spacing: 5) {
                        if focusedRegion != nil {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        Text(focusedRegion?.group.displayName ?? "Stored on this Mac")
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(focusedRegion == nil)

                Text(totalSize(of: scopeSessions))
                    .font(Theme.hero)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.3), value: totalSize(of: scopeSessions))
            }

            Text(insight)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 16)

            legend
        }
        .padding(.leading, 18)
        .padding(.trailing, 20)
        .padding(.top, 40)
        .padding(.bottom, 14)
        // Hidden until the first scan finishes, so it never flashes "Zero kB".
        .opacity(hasAppeared ? 1 : 0)
    }

    /// Says the conclusion in words, so the map is never the only way to read it.
    private var insight: String {
        let forgotten = scopeSessions.filter { $0.isDeletable && $0.isOlder(thanDays: 30) }
        let forgottenText =
            forgotten.isEmpty
            ? "Nothing here has gone unused for a month."
            : "\(sessionCount(forgotten).lowercased()) unused for a month, \(totalSize(of: forgotten))."

        if let region = focusedRegion {
            return "\(region.source.displayName). \(forgottenText)"
        }
        guard let largest = regions.max(by: { $0.group.totalSize < $1.group.totalSize }) else {
            return "No sessions yet."
        }
        let size = largest.group.totalSize.formatted(.byteCount(style: .file))
        return "Most of it is \(largest.group.displayName), at \(size). \(forgottenText)"
    }

    private var legend: some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack(spacing: 12) {
                ForEach(SessionSource.allCases) { source in
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 2.5)
                            .fill(Theme.color(for: source))
                            .frame(width: 10, height: 10)
                        Text(source.displayName)
                    }
                }
            }
            HStack(spacing: 6) {
                Text("Recent")
                DissolveKey()
                    .frame(width: 58, height: 10)
                Text("Forgotten")
            }
        }
        .font(.system(size: 11.5))
        .foregroundStyle(.secondary)
    }

    // MARK: Map

    /// The dots are drawn once and then moved as one flattened layer. Zooming
    /// only transforms that layer, so it never redraws thousands of dots.
    private var map: some View {
        GeometryReader { geometry in
            let bounds = CGRect(origin: .zero, size: geometry.size)
            let regionRects = Treemap.layout(
                regions.map { .init(id: $0.id, value: Double($0.group.totalSize)) },
                in: bounds
            )
            let focus = focusedRect(in: regionRects)
            let scaleX = focus.map { bounds.width / max($0.width, 1) } ?? 1
            let scaleY = focus.map { bounds.height / max($0.height, 1) } ?? 1

            ZStack(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    ForEach(regions) { region in
                        regionTile(region, rect: regionRects[region.id] ?? .zero)
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
                .drawingGroup()
                .scaleEffect(x: scaleX, y: scaleY, anchor: .topLeading)
                .offset(x: -(focus?.minX ?? 0) * scaleX, y: -(focus?.minY ?? 0) * scaleY)
                .opacity(focus == nil ? 1 : 0)

                if let region = focusedRegion {
                    let rects = Treemap.layout(
                        region.group.sessions.map { .init(id: $0.id, value: Double($0.size)) },
                        in: bounds
                    )
                    ZStack(alignment: .topLeading) {
                        ForEach(region.group.sessions) { session in
                            sessionTile(session, source: region.source, rect: rects[session.id] ?? .zero)
                                .transition(.opacity)
                        }
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
                    .transition(.opacity)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: Theme.tileRadius))
            .mask(alignment: .leading) {
                // Sweeps the map in from the left on opening.
                LinearGradient(
                    stops: [.init(color: .black, location: 0.85), .init(color: .clear, location: 1)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: hasAppeared ? geometry.size.width * 1.25 : 0)
            }
            .animation(Self.morph, value: store.sessions.map(\.id))
        }
    }

    private func focusedRect(in rects: [String: CGRect]) -> CGRect? {
        focusedRegionID.flatMap { rects[$0] }
    }

    private func regionTile(_ region: Region, rect: CGRect) -> some View {
        MemoryTile(
            title: region.group.displayName,
            detail: region.group.totalSize.formatted(.byteCount(style: .file)),
            color: Theme.color(for: region.source),
            fade: region.group.fade(),
            isInUse: region.group.sessions.contains { !$0.isDeletable },
            isSelected: region.group.sessions.contains { $0.id == selectedID },
            seed: region.id.hashValueStable
        )
        .frame(width: max(rect.width - 6, 0), height: max(rect.height - 6, 0))
        .position(x: rect.midX, y: rect.midY)
        .help("\(region.group.displayPath) · \(region.source.displayName)")
        .onTapGesture {
            guard deleteFlow == .idle else { return }
            withAnimation(Self.morph) {
                if region.group.sessions.count == 1 {
                    // Nothing to zoom into, so go straight to the session.
                    let id = region.group.sessions[0].id
                    selectedID = selectedID == id ? nil : id
                } else {
                    focusedRegionID = region.id
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(region.group.displayName), \(region.group.sessions.count) sessions, \(region.group.totalSize.formatted(.byteCount(style: .file)))")
        .accessibilityAddTraits(.isButton)
    }

    private func sessionTile(_ session: Session, source: SessionSource, rect: CGRect) -> some View {
        let tile = MemoryTile(
            title: session.title ?? "No Message",
            detail: session.size.formatted(.byteCount(style: .file)),
            color: Theme.color(for: source),
            fade: session.fade(),
            isInUse: !session.isDeletable,
            isSelected: session.id == selectedID,
            seed: session.id.hashValueStable
        )
        .frame(width: max(rect.width - 6, 0), height: max(rect.height - 6, 0))

        return Group {
            if shreddingIDs.contains(session.id) && !reduceMotion {
                Shredded { tile }
            } else {
                tile
            }
        }
        .position(x: rect.midX, y: rect.midY)
        .opacity(drag?.sessions.contains(session) == true ? 0.35 : 1)
        .help(session.title ?? "No Message")
        .onTapGesture {
            guard deleteFlow == .idle else { return }
            withAnimation(Self.morph) { selectedID = session.id == selectedID ? nil : session.id }
        }
        .gesture(
            DragGesture(minimumDistance: 6, coordinateSpace: .named(Self.windowSpace))
                .onChanged { dragChanged(session, to: $0.location) }
                .onEnded { _ in dragEnded() }
        )
        .contextMenu {
            Button("Show in Finder") { store.reveal(session) }
        }
        .accessibilityElement()
        .accessibilityLabel("\(session.title ?? "No Message"), \(session.size.formatted(.byteCount(style: .file)))")
        .accessibilityAddTraits(.isButton)
    }

    private func goBack() {
        guard deleteFlow == .idle || isConfirming else { return }
        withAnimation(Self.morph) {
            if isConfirming {
                deleteFlow = .idle
            } else if selectedID != nil {
                selectedID = nil
            } else {
                focusedRegionID = nil
            }
        }
    }

    private var isConfirming: Bool {
        if case .confirming = deleteFlow { true } else { false }
    }

    // MARK: Deleting

    private func requestDelete() {
        guard let selectedSession, selectedSession.isDeletable, deleteFlow == .idle else { return }
        withAnimation(Self.morph) { deleteFlow = .confirming([selectedSession]) }
    }

    /// The tile is shredded first and removed for real afterwards, so a session
    /// that fails to delete can simply reappear with its reason.
    private func delete(_ sessions: [Session]) {
        withAnimation(Self.morph) { deleteFlow = .deleting(sessions) }

        Task {
            if !reduceMotion {
                try? await Task.sleep(for: .seconds(Shredded<EmptyView>.duration))
            }
            await store.delete(sessions)

            if store.failureMessage == nil {
                withAnimation(Self.morph) { deleteFlow = .finished(freed: totalSize(of: sessions)) }
                try? await Task.sleep(for: .seconds(1.4))
            }
            withAnimation(Self.morph) {
                selectedID = nil
                deleteFlow = .idle
            }
        }
    }

    private func dragChanged(_ session: Session, to location: CGPoint) {
        guard deleteFlow == .idle, session.isDeletable else { return }

        let isOverZone = showsPanel && detailFrame.insetBy(dx: -10, dy: -10).contains(location)
        if drag == nil {
            withAnimation(Self.morph) {
                drag = CardDrag(sessions: [session], location: location, isOverZone: isOverZone)
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

    // MARK: Detail

    /// One panel that changes shape: the session's details, then a place to drop
    /// it, then the confirmation, then the result.
    private var detailPanel: some View {
        ZStack {
            if drag != nil || deleteFlow != .idle {
                DeleteZone(
                    isDragging: drag != nil,
                    isOverZone: drag?.isOverZone == true,
                    flow: deleteFlow,
                    onCancel: { withAnimation(Self.morph) { deleteFlow = .idle } },
                    onConfirm: delete
                )
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            } else if let selectedSession {
                SessionInspector(session: selectedSession, store: store, onDelete: requestDelete)
                    .id(selectedSession.id)
                    .transition(.opacity)
            }
        }
        .frame(width: Self.panelWidth)
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
}

extension String {
    /// A hash that stays the same between launches, unlike `hashValue`, so a
    /// tile keeps its pattern.
    fileprivate var hashValueStable: Int {
        utf8.reduce(5381) { ($0 &* 33 &+ Int($1)) & 0xFFFF_FFFF }
    }
}

/// One tile of the map: a card sized by how much it stores, whose right edge
/// breaks into dots as it's forgotten.
private struct MemoryTile: View {
    let title: String
    let detail: String
    let color: Color
    let fade: Double
    let isInUse: Bool
    let isSelected: Bool
    let seed: Int

    @State private var isHovered = false

    var body: some View {
        GeometryReader { geometry in
            let shape = RoundedRectangle(cornerRadius: Theme.tileRadius)

            ZStack(alignment: .topLeading) {
                color.opacity(isSelected ? 0.14 : (isHovered ? 0.1 : 0.06))
                FadingEdge(color: color, fade: fade, seed: seed)

                if geometry.size.width > 84, geometry.size.height > 52 {
                    label(in: geometry.size)
                }
            }
            .clipShape(shape)
            .overlay {
                if isSelected {
                    shape.strokeBorder(color.opacity(0.5))
                }
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }

    private func label(in size: CGSize) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                if isInUse {
                    Circle()
                        .fill(.green)
                        .frame(width: 7, height: 7)
                }
                Text(title)
                    .font(.system(size: 13))
                    .lineLimit(2)
            }
            Spacer(minLength: 4)
            Text(detail)
                .font(.system(size: numberSize(in: size), weight: .light, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(14)
        .frame(maxWidth: size.width * (1 - FadingEdge.share(fade: fade)), maxHeight: .infinity, alignment: .topLeading)
    }

    /// Bigger tiles get bigger numbers, within the type scale.
    private func numberSize(in size: CGSize) -> CGFloat {
        min(max(min(size.width / 7, size.height / 3.5), 17), 44)
    }
}

/// The dissolving edge of a tile. It stays a sliver on recent sessions, so a
/// screen of them is calm, and spreads across the card only with age.
private struct FadingEdge: View {
    let color: Color
    let fade: Double
    let seed: Int

    private static let pitch: CGFloat = 8

    /// How much of the tile's width the dots cover.
    static func share(fade: Double) -> CGFloat {
        CGFloat(0.05 + 0.5 * fade)
    }

    var body: some View {
        Canvas(rendersAsynchronously: false) { context, size in
            let width = size.width * Self.share(fade: fade)
            let columns = Int(width / Self.pitch) + 1
            let rows = Int(size.height / Self.pitch) + 1
            var dots = Path()

            for column in 0..<columns {
                let along = Double(column) / Double(max(columns - 1, 1))
                for row in 0..<rows where Self.noise(column, row, seed) > 0.25 + along * 0.65 {
                    let diameter = Self.pitch * CGFloat(0.72 - 0.42 * along)
                    dots.addEllipse(
                        in: CGRect(
                            x: size.width - CGFloat(column + 1) * Self.pitch,
                            y: CGFloat(row) * Self.pitch,
                            width: diameter,
                            height: diameter
                        )
                    )
                }
            }
            context.fill(dots, with: .color(color.opacity(0.55)))
        }
    }

    private static func noise(_ column: Int, _ row: Int, _ seed: Int) -> Double {
        let value = sin(Double(column) * 12.9898 + Double(row) * 78.233 + Double(seed % 997) * 0.37) * 43758.5453
        return value - value.rounded(.down)
    }
}

/// The small sample in the legend showing what fading looks like.
private struct DissolveKey: View {
    var body: some View {
        Canvas { context, size in
            let count = 9
            let pitch = size.width / CGFloat(count)
            for index in 0..<count {
                let along = Double(index) / Double(count - 1)
                let diameter = pitch * CGFloat(1.15 - 0.8 * along)
                let rect = CGRect(
                    x: CGFloat(index) * pitch,
                    y: (size.height - diameter) / 2,
                    width: diameter,
                    height: diameter
                )
                context.fill(Path(ellipseIn: rect), with: .color(Color.secondary.opacity(1 - along * 0.6)))
            }
        }
        .accessibilityHidden(true)
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
