import AmnesiaCore
import SwiftUI

/// Draws one viewport of GPU stamps and keeps the native hit targets in the scrolling rows.
struct LibrarySessionReel: View {
    let groups: [LibraryLaunchGroup]
    let collections: [SessionCollection]
    let onDirectory: (LibraryLaunchGroup) -> Void
    let onOpen: (Session, CGRect?) -> Void
    let onCollect: (SessionReference, UUID) -> Void

    @State private var rowFrames: [String: ReelRowFrame] = [:]
    @State private var hovered: SessionReference?
    @FocusState private var focused: SessionReference?

    private static let viewport = "session-reel-viewport"

    var body: some View {
        let highlighted = (hovered ?? focused).flatMap { reference in
            groups.lazy.flatMap(\.sessions).first { SessionReference($0) == reference }
        }
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Launch directory")
                    .frame(width: ReelLayout.labelWidth, alignment: .leading)
                if let highlighted {
                    Text(verbatim: displayTitle(highlighted))
                        .lineLimit(1)
                        .foregroundStyle(sourceTint(highlighted.source))
                        .accessibilityHidden(true)
                } else {
                    Text("Newest first · drag to collect")
                }
                Spacer()
                sourceLabel(.codex, symbol: "−")
                sourceLabel(.claudeCode, symbol: "=").padding(.leading, 8)
                Text("Total").frame(width: ReelLayout.countWidth, alignment: .trailing).padding(.leading, 7)
            }
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(LibraryAppearance.muted)
            .padding(.horizontal, 13)
            .frame(height: 30)
            .background(LibraryAppearance.chrome.opacity(0.44))
            .accessibilityElement(children: .combine)
            LibraryAppearance.rule.frame(height: 1)
            GeometryReader { proxy in
                let layout = ReelLayout(width: proxy.size.width)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(groups) { group in
                            row(group, layout: layout)
                                .background {
                                    GeometryReader { row in
                                        Color.clear.preference(key: ReelFrameKey.self, value: [group.id: ReelRowFrame(
                                            viewport: row.frame(in: .named(Self.viewport)),
                                            workspace: row.frame(in: .named(LibraryReaderCoordinates.name))
                                        )])
                                    }
                                }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 18)
                }
                .coordinateSpace(name: Self.viewport)
                .onPreferenceChange(ReelFrameKey.self) { rowFrames = $0 }
                .overlay(alignment: .topLeading) {
                    LibrarySessionMarks(marks: marks(in: proxy.size, layout: layout))
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                .clipped()
            }
        }
        .accessibilityIdentifier("session-reel")
    }

    private func row(_ group: LibraryLaunchGroup, layout: ReelLayout) -> some View {
        let shown = layout.visibleCount(for: group.sessions.count)
        let hidden = group.sessions.count - shown
        return HStack(spacing: 0) {
            Button { onDirectory(group) } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: group.title)
                        .font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(verbatim: pathLabel(group.path))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(LibraryAppearance.muted)
                        .lineLimit(1).truncationMode(.middle)
                }
                .padding(.trailing, 14)
                .frame(width: ReelLayout.labelWidth, height: ReelLayout.rowHeight, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(pathLabel(group.path))
            .accessibilityLabel("\(group.title), \(group.sessions.count) sessions")
            .accessibilityValue(pathLabel(group.path))
            .accessibilityHint("Show all sessions from this directory")

            HStack(spacing: ReelLayout.gap) {
                ForEach(Array(group.sessions.prefix(shown).enumerated()), id: \.element.fileURL) { index, session in
                    stamp(session, source: rowFrames[group.id].map { stampFrame(at: index, in: $0.workspace) })
                }
                if hidden > 0 {
                    Button { onDirectory(group) } label: {
                        Text("+\(hidden)")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(LibraryAppearance.muted)
                            .lineLimit(1).minimumScaleFactor(0.6)
                            .frame(width: ReelLayout.overflowWidth, height: ReelLayout.hitHeight)
                            .background(LibraryAppearance.chrome, in: RoundedRectangle(cornerRadius: 4))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Show \(hidden) more sessions in \(group.title)")
                }
            }
            Spacer(minLength: 6)
            Text(group.sessions.count.formatted())
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .monospacedDigit().foregroundStyle(LibraryAppearance.muted)
                .frame(width: ReelLayout.countWidth, alignment: .trailing)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, ReelLayout.inset)
        .frame(height: ReelLayout.rowHeight)
        .overlay(alignment: .bottom) {
            LibraryAppearance.rule.opacity(0.62).frame(height: 1).allowsHitTesting(false).accessibilityHidden(true)
        }
    }

    private func stamp(_ session: Session, source: CGRect?) -> some View {
        let reference = SessionReference(session)
        let title = displayTitle(session)
        let time = session.updatedAt.formatted(date: .abbreviated, time: .shortened)
        return Button { onOpen(session, source) } label: {
            Color.clear
                .frame(width: ReelLayout.stampWidth, height: ReelLayout.hitHeight)
                .contentShape(Rectangle())
                .overlay {
                    if focused == reference {
                        RoundedRectangle(cornerRadius: 4).strokeBorder(LibraryAppearance.ink.opacity(0.8), lineWidth: 1)
                            .allowsHitTesting(false)
                    }
                }
        }
        .buttonStyle(.plain)
        .focused($focused, equals: reference)
        .onHover { inside in
            if inside { hovered = reference }
            else if hovered == reference { hovered = nil }
        }
        .help("\(title)\n\(session.source.displayName) · \(time)")
        .accessibilityLabel(title)
        .accessibilityValue("\(session.source.displayName), \(time)")
        .accessibilityHint("Open this session, or drag it to a collection")
        .draggable(reference) {
            HStack(spacing: 7) {
                Circle().fill(sourceTint(session.source)).frame(width: 5, height: 5)
                Text(verbatim: title).font(.system(size: 12, weight: .medium)).lineLimit(1)
            }
            .frame(maxWidth: 235)
            .padding(.horizontal, 11).padding(.vertical, 7)
            .background(LibraryAppearance.index, in: RoundedRectangle(cornerRadius: 7))
        }
        .contextMenu {
            if !collections.isEmpty {
                Menu("Add to Collection") {
                    ForEach(collections) { collection in
                        Button(collection.name) { onCollect(reference, collection.id) }
                            .disabled(collection.members.contains(reference))
                    }
                }
            }
        }
    }

    private func sourceLabel(_ source: SessionSource, symbol: String) -> some View {
        HStack(spacing: 4) {
            Text(symbol).foregroundStyle(sourceTint(source)).accessibilityHidden(true)
            Text(source.displayName).fixedSize()
        }
    }

    private func marks(in size: CGSize, layout: ReelLayout) -> [LibrarySessionMark] {
        groups.flatMap { group -> [LibrarySessionMark] in
            guard let frame = rowFrames[group.id]?.viewport, frame.maxY > 0, frame.minY < size.height else { return [] }
            return group.sessions.prefix(layout.visibleCount(for: group.sessions.count)).enumerated().map { ordinal, session in
                let ref = SessionReference(session)
                return LibrarySessionMark(
                    frame: stampFrame(at: ordinal, in: frame),
                    isClaude: session.source == .claudeCode,
                    isEmphasized: hovered == ref || focused == ref
                )
            }
        }
    }

    private func stampFrame(at ordinal: Int, in row: CGRect) -> CGRect {
        CGRect(
            x: row.minX + ReelLayout.inset + ReelLayout.labelWidth + CGFloat(ordinal) * (ReelLayout.stampWidth + ReelLayout.gap) + 2,
            y: row.midY - 14,
            width: ReelLayout.stampWidth - 4,
            height: 28
        )
    }
}

private struct ReelLayout {
    static let inset: CGFloat = 13
    static let labelWidth: CGFloat = 174
    static let rowHeight: CGFloat = 53
    static let stampWidth: CGFloat = 25
    static let hitHeight: CGFloat = 38
    static let gap: CGFloat = 2
    static let overflowWidth: CGFloat = 37
    static let countWidth: CGFloat = 37

    let width: CGFloat

    func visibleCount(for count: Int) -> Int {
        let space = max(0, width - 2 * Self.inset - Self.labelWidth - Self.countWidth - 8)
        let capacity = max(1, Int((space + Self.gap) / (Self.stampWidth + Self.gap)))
        if count <= capacity { return count }
        return max(1, Int((space - Self.overflowWidth) / (Self.stampWidth + Self.gap)))
    }
}

private struct ReelRowFrame: Equatable {
    let viewport: CGRect
    let workspace: CGRect
}

private struct ReelFrameKey: PreferenceKey {
    static var defaultValue: [String: ReelRowFrame] { [:] }

    static func reduce(value: inout [String: ReelRowFrame], nextValue: () -> [String: ReelRowFrame]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
