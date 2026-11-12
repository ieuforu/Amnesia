import AmnesiaCore
import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum SessionLibraryDrag {
    static let typeIdentifier = "com.ieuforu.amnesia.session-reference"

    @MainActor
    static var pasteboardType: NSPasteboard.PasteboardType { .init(typeIdentifier) }

    @MainActor
    static func pasteboardItem(for reference: SessionReference) -> NSPasteboardItem? {
        guard let data = try? JSONEncoder().encode(reference) else { return nil }
        let item = NSPasteboardItem()
        item.setData(data, forType: pasteboardType)
        return item
    }

    @MainActor
    static func references(from pasteboard: NSPasteboard) -> Set<SessionReference> {
        guard let items = pasteboard.pasteboardItems else { return [] }
        let decoder = JSONDecoder()
        var references = Set<SessionReference>()
        for item in items {
            guard let data = item.data(forType: pasteboardType), data.count <= 4_096,
                  let reference = try? decoder.decode(SessionReference.self, from: data)
            else { return [] }
            references.insert(reference)
        }
        return references
    }
}

extension SessionReference: Transferable {
    public static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(contentType: UTType(exportedAs: SessionLibraryDrag.typeIdentifier, conformingTo: .data)) {
            try JSONEncoder().encode($0)
        } importing: { data in
            guard data.count <= 4_096 else { throw CocoaError(.coderReadCorrupt) }
            return try JSONDecoder().decode(SessionReference.self, from: data)
        }
        .visibility(.ownProcess)
    }
}

/// Uses AppKit's native selection and drag handling for rows while SwiftUI
/// owns the selection by session identity, independent of row position.
struct SessionLibraryTable: NSViewRepresentable {
    let sessions: [Session]
    @Binding var selection: Set<SessionReference>

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true

        let table = NSTableView()
        table.headerView = nil
        table.style = .plain
        table.backgroundColor = .clear
        table.selectionHighlightStyle = .regular
        table.rowSizeStyle = .custom
        table.rowHeight = SessionLibraryCell.compactHeight
        table.setDraggingSourceOperationMask(.copy, forLocal: true)
        table.setDraggingSourceOperationMask([], forLocal: false)
        table.intercellSpacing = .zero
        table.allowsMultipleSelection = true
        table.allowsEmptySelection = true
        table.autoresizingMask = [.width]
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.setDraggingSourceOperationMask(.copy, forLocal: true)
        table.setDraggingSourceOperationMask([], forLocal: false)
        table.setAccessibilityLabel("Sessions")
        table.setAccessibilityIdentifier("session-library-table")

        let column = NSTableColumn(identifier: .init("session"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        scroll.documentView = table
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let table = scroll.documentView as? NSTableView else { return }
        context.coordinator.update(sessions: sessions, selection: $selection, table: table, scroll: scroll)
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        private var selection: Binding<Set<SessionReference>>
        private var sessions: [Session] = []
        private var excerpts: [String?] = []
        private var references: [SessionReference] = []
        private var rowForReference: [SessionReference: Int] = [:]
        private var isUpdating = false

        init(selection: Binding<Set<SessionReference>>) {
            self.selection = selection
        }

        func update(
            sessions: [Session],
            selection: Binding<Set<SessionReference>>,
            table: NSTableView,
            scroll: NSScrollView
        ) {
            self.selection = selection
            isUpdating = true
            defer { isUpdating = false }

            if self.sessions != sessions {
                let firstVisibleRow = table.rows(in: table.visibleRect).location
                let anchor = references.indices.contains(firstVisibleRow) ? references[firstVisibleRow] : nil
                let offset = anchor == nil ? 0 : table.visibleRect.minY - table.rect(ofRow: firstVisibleRow).minY

                self.sessions = sessions
                excerpts = sessions.map { SessionLibraryCell.excerpt(for: $0) }
                references = sessions.map { SessionReference($0) }
                rowForReference.removeAll(keepingCapacity: true)
                for (row, reference) in references.enumerated() { rowForReference[reference] = row }
                table.reloadData()

                if let anchor, let row = rowForReference[anchor] {
                    let rect = table.rect(ofRow: row)
                    let origin = NSPoint(x: 0, y: rect.minY + min(offset, max(0, rect.height - 1)))
                    scroll.contentView.scroll(to: origin)
                    scroll.reflectScrolledClipView(scroll.contentView)
                } else if firstVisibleRow != NSNotFound {
                    scroll.contentView.scroll(to: .zero)
                    scroll.reflectScrolledClipView(scroll.contentView)
                }
            }

            let selectedRows = IndexSet(selection.wrappedValue.compactMap { rowForReference[$0] })
            if table.selectedRowIndexes != selectedRows {
                table.selectRowIndexes(selectedRows, byExtendingSelection: false)
            }
        }

        func numberOfRows(in tableView: NSTableView) -> Int { sessions.count }

        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            guard excerpts.indices.contains(row), excerpts[row] != nil else {
                return SessionLibraryCell.compactHeight
            }
            return SessionLibraryCell.excerptHeight
        }

        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            let identifier = NSUserInterfaceItemIdentifier("library-session-row")
            let rowView = (tableView.makeView(withIdentifier: identifier, owner: nil) as? SessionLibraryRow)
                ?? SessionLibraryRow()
            rowView.identifier = identifier
            return rowView
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            let identifier = NSUserInterfaceItemIdentifier("session-cell")
            let cell = (tableView.makeView(withIdentifier: identifier, owner: nil) as? SessionLibraryCell)
                ?? SessionLibraryCell()
            cell.identifier = identifier
            cell.configure(with: sessions[row], excerpt: excerpts[row])
            return cell
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isUpdating, let table = notification.object as? NSTableView else { return }
            let selected = Set(table.selectedRowIndexes.compactMap { references.indices.contains($0) ? references[$0] : nil })
            if selection.wrappedValue != selected { selection.wrappedValue = selected }
        }

        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
            guard references.indices.contains(row) else { return nil }
            return SessionLibraryDrag.pasteboardItem(for: references[row])
        }

        func tableView(
            _ tableView: NSTableView,
            draggingSession session: NSDraggingSession,
            willBeginAt screenPoint: NSPoint,
            forRowIndexes rowIndexes: IndexSet
        ) {
            session.draggingFormation = .pile
        }
    }
}

@MainActor
private enum SessionLibraryInk {
    static let codex = adaptive(0x5650BD, 0xB5AEFF)
    static let claude = adaptive(0xA84B2E, 0xFFA78B)
    static let primary = adaptive(0x242130, 0xF0EEF6)
    static let secondary = adaptive(0x605B6D, 0xBDB7CB)
    static let muted = adaptive(0x6C6579, 0xA9A2B7)
    static let separator = adaptive(0x312645, 0xD7CDEE, alpha: 0.11)
    static let selection = adaptive(0x5650BD, 0xB5AEFF, alpha: 0.13)

    private static func adaptive(_ light: UInt32, _ dark: UInt32, alpha: CGFloat = 1) -> NSColor {
        NSColor(name: nil) { appearance in
            let rgb = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(
                srgbRed: CGFloat((rgb >> 16) & 255) / 255,
                green: CGFloat((rgb >> 8) & 255) / 255,
                blue: CGFloat(rgb & 255) / 255,
                alpha: alpha
            )
        }
    }
}

/// Draws Amnesia's selection and separators without changing AppKit selection or focus behavior.
@MainActor
private final class SessionLibraryRow: NSTableRowView {
    override func drawBackground(in dirtyRect: NSRect) {
        let pixel = 1 / (window?.backingScaleFactor ?? 1)
        let y = isFlipped ? bounds.maxY - pixel : bounds.minY
        SessionLibraryInk.separator.setFill()
        NSRect(x: 16, y: y, width: max(0, bounds.width - 32), height: pixel).fill()
    }

    override func drawSelection(in dirtyRect: NSRect) {
        guard isSelected else { return }
        SessionLibraryInk.selection.setFill()
        bounds.insetBy(dx: 0, dy: 1).fill()
        SessionLibraryInk.codex.setFill()
        NSRect(x: 0, y: bounds.midY - 11, width: 2, height: 22).fill()
    }
}

@MainActor
private final class SessionLibraryCell: NSTableCellView {
    static let compactHeight: CGFloat = 45
    static let excerptHeight: CGFloat = 58

    private let titleLabel = NSTextField(labelWithString: "")
    private let dateLabel = NSTextField(labelWithString: "")
    private let excerptLabel = NSTextField(labelWithString: "")
    private let sourceLabel = NSTextField(labelWithString: "")
    private let pathLabel = NSTextField(labelWithString: "")
    private let sourceDot = SessionSourceDot()
    private var compactMetadataTop: NSLayoutConstraint!
    private var excerptMetadataTop: NSLayoutConstraint!

    init() {
        super.init(frame: .zero)

        textField = titleLabel
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        excerptLabel.font = .systemFont(ofSize: 11.5)
        sourceLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        pathLabel.font = .systemFont(ofSize: 10)
        dateLabel.font = .monospacedDigitSystemFont(ofSize: 10.5, weight: .medium)
        dateLabel.alignment = .right
        titleLabel.textColor = SessionLibraryInk.primary
        excerptLabel.textColor = SessionLibraryInk.secondary
        pathLabel.textColor = SessionLibraryInk.muted
        dateLabel.textColor = SessionLibraryInk.muted

        for label in [titleLabel, dateLabel, excerptLabel, sourceLabel, pathLabel] {
            label.maximumNumberOfLines = 1
            label.lineBreakMode = .byTruncatingTail
        }
        for label in [titleLabel, excerptLabel, pathLabel] {
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        pathLabel.lineBreakMode = .byTruncatingMiddle
        sourceLabel.setContentHuggingPriority(.required, for: .horizontal)
        sourceLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let heading = NSStackView(views: [titleLabel, dateLabel])
        heading.alignment = .firstBaseline
        heading.distribution = .fill
        heading.spacing = 10
        let provenance = NSStackView(views: [sourceDot, sourceLabel])
        provenance.alignment = .centerY
        provenance.spacing = 5
        let metadata = NSStackView(views: [provenance, pathLabel])
        metadata.alignment = .centerY
        metadata.distribution = .fill
        metadata.spacing = 9

        let lines = NSView()
        lines.translatesAutoresizingMaskIntoConstraints = false
        addSubview(lines)
        for view in [heading, excerptLabel, metadata] {
            view.translatesAutoresizingMaskIntoConstraints = false
            lines.addSubview(view)
        }
        compactMetadataTop = metadata.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 3)
        excerptMetadataTop = metadata.topAnchor.constraint(equalTo: excerptLabel.bottomAnchor, constant: 3)
        NSLayoutConstraint.activate([
            lines.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            lines.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            lines.centerYAnchor.constraint(equalTo: centerYAnchor),
            heading.leadingAnchor.constraint(equalTo: lines.leadingAnchor),
            heading.topAnchor.constraint(equalTo: lines.topAnchor),
            heading.widthAnchor.constraint(equalTo: lines.widthAnchor),
            excerptLabel.leadingAnchor.constraint(equalTo: lines.leadingAnchor),
            excerptLabel.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 2),
            excerptLabel.widthAnchor.constraint(equalTo: lines.widthAnchor),
            metadata.leadingAnchor.constraint(equalTo: lines.leadingAnchor),
            metadata.widthAnchor.constraint(equalTo: lines.widthAnchor),
            metadata.bottomAnchor.constraint(equalTo: lines.bottomAnchor),
            compactMetadataTop,
            sourceDot.widthAnchor.constraint(equalToConstant: 6),
            sourceDot.heightAnchor.constraint(equalToConstant: 6),
            dateLabel.widthAnchor.constraint(equalToConstant: 104),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    func configure(with session: Session, excerpt: String?) {
        let color = session.source == .codex ? SessionLibraryInk.codex : SessionLibraryInk.claude
        titleLabel.stringValue = Self.oneLine(session.title) ?? "Untitled session"
        excerptLabel.stringValue = excerpt ?? ""
        excerptLabel.isHidden = excerpt == nil
        if excerpt == nil {
            excerptMetadataTop.isActive = false
            compactMetadataTop.isActive = true
        } else {
            compactMetadataTop.isActive = false
            excerptMetadataTop.isActive = true
        }
        sourceDot.tint = color
        sourceLabel.textColor = color
        sourceLabel.stringValue = session.source.displayName
        let path = session.projectPath.map { ($0 as NSString).abbreviatingWithTildeInPath }
        pathLabel.stringValue = path.flatMap { $0 == "~" ? nil : ($0 as NSString).lastPathComponent } ?? ""
        let date = session.updatedAt
        dateLabel.stringValue = Calendar.current.isDateInToday(date)
            ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
        toolTip = path
    }

    static func excerpt(for session: Session) -> String? {
        let excerpt = oneLine(session.latestUserMessage) ?? oneLine(session.firstMessage)
        return excerpt == oneLine(session.title) ? nil : excerpt
    }

    private static func oneLine(_ value: String?) -> String? {
        guard let value else { return nil }
        let line = value.prefix(400).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return line.isEmpty ? nil : line
    }
}

@MainActor
private final class SessionSourceDot: NSView {
    var tint = NSColor.clear { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        tint.setFill()
        NSBezierPath(ovalIn: bounds).fill()
    }
}
