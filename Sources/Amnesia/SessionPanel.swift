import AmnesiaCore
import SwiftUI

/// The menu bar panel. It draws no background of its own, so the system's
/// glass shows through, and follows the layout of native menu bar menus.
///
/// It only displays what it is given, so it can render sample data as easily
/// as real sessions.
struct SessionPanel: View {
    let groups: [SessionGroup]
    let isScanning: Bool
    let onRefresh: () -> Void

    @State private var listHeight: CGFloat = 0

    private static let maxListHeight: CGFloat = 440

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
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

    private var summary: String {
        let sessions = groups.flatMap(\.sessions)
        let size = sessions.reduce(0) { $0 + $1.size }
        return "\(sessions.count) · \(size.formatted(.byteCount(style: .file)))"
    }

    @ViewBuilder
    private var content: some View {
        if groups.isEmpty {
            Text(isScanning ? "Scanning…" : "No Sessions")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(groups) { group in
                        SessionGroupView(group: group)
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

    private var actions: some View {
        VStack(spacing: 0) {
            MenuRow(title: "Refresh", action: onRefresh)
                .keyboardShortcut("r")
                .disabled(isScanning)
            MenuRow(title: "Quit Amnesia") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
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
                SessionRow(session: session)
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

    var body: some View {
        HStack(spacing: 9) {
            SourceIcon(source: session.source)

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
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .modifier(HoverHighlight())
    }
}

private struct SourceIcon: View {
    let source: SessionSource

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: 18)
            .help(source.displayName)
            .accessibilityLabel(source.displayName)
    }

    private var symbol: String {
        switch source {
        case .claudeCode: "asterisk"
        case .codex: "terminal"
        }
    }
}
