import AmnesiaCore
import SwiftUI

/// The conversation view in the library. Storage retains its own inspector
/// because its actions and the information it emphasizes are different.
struct LibraryReader<Actions: View>: View {
    let session: Session
    let store: SessionStore
    private let columnWidth: CGFloat?
    private let actions: Actions

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var loaded: LoadedPreview?
    @State private var filesExpanded = false

    init(session: Session, store: SessionStore, columnWidth: CGFloat? = nil, @ViewBuilder actions: () -> Actions) {
        self.session = session
        self.store = store
        self.columnWidth = columnWidth
        self.actions = actions()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            articleColumn(header)
            separator
            conversation
            separator
            articleColumn(fileShelf).background(palette.shelf)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.paper)
        .task(id: previewRequest) {
            let request = previewRequest
            let result = await store.detail(for: session)
            guard !Task.isCancelled else { return }
            let parsing = Task.detached(priority: .userInitiated) {
                var messages: [RenderedMessage] = []
                for message in result.messages {
                    guard !Task.isCancelled else { break }
                    messages.append(RenderedMessage(message: message, markdown: TranscriptMarkdown(message.text)))
                }
                return messages
            }
            let rendered = await withTaskCancellationHandler {
                await parsing.value
            } onCancel: {
                parsing.cancel()
            }
            guard !Task.isCancelled else { return }
            loaded = LoadedPreview(session: request.identity, detail: result, messages: rendered)
        }
        .onChange(of: previewRequest.identity) { filesExpanded = false }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 9) {
                HStack(spacing: 5) {
                    Circle().fill(sourceColor).frame(width: 5, height: 5)
                        .accessibilityHidden(true)
                    Text(session.source.displayName)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                }
                .foregroundStyle(sourceColor)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(sourceColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 5))

                if session.isActive {
                    Text("Protected")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(palette.muted)
                        .help("This session is open or was modified recently.")
                }
                Spacer(minLength: 4)
                Text(session.updatedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(palette.muted)
                    .lineLimit(1)
            }
            Text(verbatim: displayTitle(session))
                .font(.system(size: 21, weight: .semibold))
                .tracking(-0.35)
                .foregroundStyle(palette.ink)
                .lineLimit(3)
                .textSelection(.enabled)
                .accessibilityAddTraits(.isHeader)
            if let directory = session.projectPath {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                        .font(.system(size: 10, weight: .medium))
                        .accessibilityHidden(true)
                    Text(verbatim: (directory as NSString).abbreviatingWithTildeInPath)
                        .font(.system(size: 10, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .help(directory)
                }
                .foregroundStyle(palette.muted)
            }
            HStack(spacing: 7) { actions }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var conversation: some View {
        if let preview {
            if preview.messages.isEmpty {
                readerNotice("No conversation preview", symbol: "text.alignleft")
            } else {
                ScrollView {
                    articleColumn(
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(preview.messages) { message in
                                if message.id == preview.detail.omittedAfter {
                                    omittedMarker
                                }
                                turn(message)
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 16)
                    )
                }
            }
        } else {
            readerNotice("Opening conversation…", symbol: "ellipsis")
        }
    }

    private func articleColumn<Content: View>(_ content: Content) -> some View {
        content.frame(maxWidth: columnWidth ?? .infinity).frame(maxWidth: .infinity)
    }

    private func turn(_ rendered: RenderedMessage) -> some View {
        let isUser = rendered.message.role == .user
        let marker = isUser ? sourceColor : palette.muted
        return VStack(alignment: .leading, spacing: 6) {
            Text(isUser ? "YOU" : session.source.displayName.uppercased())
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1.1)
                .foregroundStyle(marker)
            TranscriptMarkdownView(markdown: rendered.markdown, ink: palette.ink, muted: palette.muted, rule: palette.rule)
                .tint(sourceColor)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if isUser {
                RoundedRectangle(cornerRadius: 7)
                    .fill(sourceColor.opacity(colorScheme == .dark ? 0.11 : 0.065))
            }
        }
        .overlay(alignment: .leading) {
            if isUser {
                Capsule()
                    .fill(sourceColor.opacity(0.7))
                    .frame(width: 2)
                    .padding(.vertical, 9)
                    .accessibilityHidden(true)
            }
        }
    }

    private var omittedMarker: some View {
        HStack(spacing: 8) {
            separator
            Text("Part of the transcript is omitted")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(palette.muted)
                .fixedSize()
            separator
        }
        .padding(.vertical, 5)
    }

    private func readerNotice(_ title: LocalizedStringKey, symbol: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol).accessibilityHidden(true)
            Text(title)
        }
        .font(.system(size: 12))
        .foregroundStyle(palette.muted)
        .padding(20)
        .frame(maxWidth: columnWidth ?? .infinity, maxHeight: .infinity, alignment: .topLeading)
        .frame(maxWidth: .infinity)
    }

    private var fileShelf: some View {
        let files = detail?.files ?? []
        return VStack(alignment: .leading, spacing: 0) {
            if filesExpanded, !files.isEmpty {
                ViewThatFits(in: .vertical) {
                    fileList(files).fixedSize(horizontal: false, vertical: true)
                    ScrollView { fileList(files) }.frame(height: 118)
                }
                .frame(maxHeight: 118)
                .transition(.opacity)
                separator
            }
            HStack(spacing: 9) {
                Button {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
                        filesExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: filesExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8, weight: .semibold))
                        Text("Files")
                        if !files.isEmpty {
                            Text(files.count, format: .number)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(palette.muted)
                        }
                    }
                }
                .buttonStyle(ReaderButtonStyle(palette: palette))
                .accessibilityValue(filesExpanded ? "Expanded" : "Collapsed")
                .disabled(files.isEmpty)

                Spacer(minLength: 4)
                Button {
                    store.reveal(session)
                } label: {
                    Label("Show in Finder", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(ReaderButtonStyle(palette: palette))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
        }
    }

    private func fileList(_ files: [StoredFile]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(files) { file in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(verbatim: file.label)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(palette.ink)
                        Spacer(minLength: 6)
                        Text(file.size, format: .byteCount(style: .file))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(palette.muted)
                            .fixedSize()
                    }
                    Text(verbatim: file.path)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(palette.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .help(file.path)
                }
            }
        }
        .padding(.horizontal, 19)
        .padding(.vertical, 12)
    }

    private var separator: some View {
        Rectangle().fill(palette.rule).frame(height: 1)
    }

    private var palette: ReaderPalette { ReaderPalette(dark: colorScheme == .dark, inWorkspace: columnWidth != nil) }

    private var sourceColor: Color { palette.source(session.source) }

    private var previewRequest: PreviewRequest {
        PreviewRequest(
            identity: PreviewIdentity(reference: SessionReference(session), file: session.fileURL),
            date: session.updatedAt,
            size: session.size
        )
    }

    private var detail: SessionDetail? {
        preview?.detail
    }

    private var preview: LoadedPreview? {
        loaded?.session == previewRequest.identity ? loaded : nil
    }

    private struct PreviewIdentity: Hashable {
        let reference: SessionReference
        let file: URL
    }

    private struct PreviewRequest: Hashable {
        let identity: PreviewIdentity
        let date: Date
        let size: Int64
    }

    private struct LoadedPreview {
        let session: PreviewIdentity
        let detail: SessionDetail
        let messages: [RenderedMessage]
    }
}

private struct RenderedMessage: Identifiable, Sendable {
    let message: TranscriptMessage
    let markdown: TranscriptMarkdown

    var id: Int { message.id }
}

private struct ReaderPalette {
    let dark: Bool
    let inWorkspace: Bool

    var paper: Color { inWorkspace ? LibraryAppearance.index : (dark ? Color(red: 0.105, green: 0.101, blue: 0.126) : Color(red: 0.991, green: 0.985, blue: 0.972)) }
    var shelf: Color { inWorkspace ? LibraryAppearance.paper : (dark ? Color(red: 0.130, green: 0.126, blue: 0.156) : Color(red: 0.970, green: 0.960, blue: 0.940)) }
    var ink: Color { inWorkspace ? LibraryAppearance.ink : (dark ? Color(red: 0.930, green: 0.917, blue: 0.902) : Color(red: 0.126, green: 0.115, blue: 0.150)) }
    var muted: Color { inWorkspace ? LibraryAppearance.muted : (dark ? Color(red: 0.691, green: 0.668, blue: 0.729) : Color(red: 0.390, green: 0.365, blue: 0.420)) }
    var rule: Color { inWorkspace ? LibraryAppearance.rule : ink.opacity(dark ? 0.15 : 0.10) }

    func source(_ source: SessionSource) -> Color {
        if inWorkspace { return sourceTint(source) }
        return switch (source, dark) {
        case (.claudeCode, false): Color(red: 0.66, green: 0.294, blue: 0.18)
        case (.claudeCode, true): Color(red: 0.99, green: 0.60, blue: 0.45)
        case (.codex, false): Color(red: 0.337, green: 0.314, blue: 0.741)
        case (.codex, true): Color(red: 0.702, green: 0.674, blue: 0.99)
        }
    }
}

private struct ReaderButtonStyle: ButtonStyle {
    let palette: ReaderPalette

    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(palette.ink.opacity(isEnabled ? 1 : 0.45))
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(
                palette.ink.opacity(configuration.isPressed ? 0.12 : (hovering && isEnabled ? 0.055 : 0)),
                in: RoundedRectangle(cornerRadius: 5)
            )
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
    }
}
