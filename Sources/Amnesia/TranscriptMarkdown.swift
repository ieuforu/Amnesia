import Foundation

/// Foundation supplies the Markdown semantics; the reader decides their visual layout.
struct TranscriptMarkdown: Sendable {
    struct Block: Sendable {
        enum Content: Sendable {
            case paragraph(AttributedString)
            case heading(level: Int, AttributedString)
            case code(language: String?, text: String)
            case table(columns: [PresentationIntent.TableColumn], rows: [[AttributedString]])
            case rule
        }

        var content: Content
        var listDepth = 0
        var listMarker: String?
        var quoted = false
    }

    let blocks: [Block]

    init(_ source: String) {
        guard let formatted = try? AttributedString(markdown: source), !formatted.characters.isEmpty else {
            blocks = [.init(content: .paragraph(AttributedString(source)))]
            return
        }

        var blocks: [Block] = []
        var seenListItems = Set<Int>()
        var table: Table?
        var segments = formatted.runs.makeIterator()
        var next = segments.next()

        while let first = next {
            let components = first.presentationIntent?.components ?? []
            let leaf = components.first
            var upperBound = first.range.upperBound
            next = segments.next()
            // Bold, links, and code can split one semantic leaf into many runs.
            while let run = next, run.presentationIntent?.components.first == leaf {
                upperBound = run.range.upperBound
                next = segments.next()
            }
            let content = Self.sanitized(AttributedString(formatted[first.range.lowerBound..<upperBound]))

            if let cell = TableCell(components) {
                if table?.id != cell.tableID {
                    if let table { blocks.append(table.block) }
                    table = Table(id: cell.tableID, columns: cell.columns, context: Self.block(.rule, components, seen: &seenListItems))
                }
                table?.set(content, at: cell)
                continue
            }
            if let pending = table {
                blocks.append(pending.block)
                table = nil
            }

            let kind: Block.Content
            switch leaf?.kind {
            case .header(let level): kind = .heading(level: level, content)
            case .codeBlock(let language):
                let text = String(content.characters)
                kind = .code(language: language, text: text.hasSuffix("\n") ? String(text.dropLast()) : text)
            case .thematicBreak: kind = .rule
            default: kind = .paragraph(content)
            }
            blocks.append(Self.block(kind, components, seen: &seenListItems))
        }
        if let table { blocks.append(table.block) }
        self.blocks = blocks
    }

    private static func sanitized(_ content: AttributedString) -> AttributedString {
        var text = content.transformingAttributes(\.link) { attribute in
            guard let url = attribute.value, let scheme = url.scheme?.lowercased(),
                  ["http", "https"].contains(scheme), let host = url.host, !host.isEmpty else {
                attribute.value = nil
                return
            }
        }
        // Transcript images appear as their labels. They aren't fetched or opened.
        text.imageURL = nil
        text.presentationIntent = nil
        return text
    }

    private static func block(
        _ content: Block.Content, _ components: [PresentationIntent.IntentType], seen: inout Set<Int>
    ) -> Block {
        var block = Block(content: content)
        var item: (identity: Int, ordinal: Int)?
        for component in components {
            switch component.kind {
            case .blockQuote:
                block.quoted = true
            case .listItem(let ordinal):
                if item == nil { item = (component.identity, ordinal) }
            case .orderedList, .unorderedList:
                if block.listDepth == 0, let item, seen.insert(item.identity).inserted {
                    block.listMarker = component.kind == .orderedList ? "\(item.ordinal)." : "•"
                }
                block.listDepth += 1
            default: break
            }
        }
        return block
    }

    private struct TableCell {
        let tableID: Int
        let columns: [PresentationIntent.TableColumn]
        let row: Int
        let column: Int

        init?(_ components: [PresentationIntent.IntentType]) {
            guard case .tableCell(let column) = components.first?.kind else { return nil }
            var row = 0
            for component in components.dropFirst() {
                switch component.kind {
                case .tableRow(let index): row = index
                case .table(let columns):
                    self.init(tableID: component.identity, columns: columns, row: row, column: column)
                    return
                default: break
                }
            }
            return nil
        }

        private init(tableID: Int, columns: [PresentationIntent.TableColumn], row: Int, column: Int) {
            self.tableID = tableID
            self.columns = columns
            self.row = row
            self.column = column
        }
    }

    private struct Table {
        let id: Int
        let columns: [PresentationIntent.TableColumn]
        var context: Block
        var rows: [[AttributedString]] = []

        mutating func set(_ content: AttributedString, at cell: TableCell) {
            guard cell.row >= 0, columns.indices.contains(cell.column) else { return }
            while rows.count <= cell.row { rows.append(Array(repeating: AttributedString(), count: columns.count)) }
            rows[cell.row][cell.column] = content
        }

        var block: Block {
            var block = context
            block.content = .table(columns: columns, rows: rows)
            return block
        }
    }
}
