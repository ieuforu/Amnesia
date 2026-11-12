import SwiftUI

struct TranscriptMarkdownView: View {
    let markdown: TranscriptMarkdown
    let ink: Color
    let muted: Color
    let rule: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(markdown.blocks.indices, id: \.self) { index in
                block(markdown.blocks[index])
            }
        }
        .foregroundStyle(ink)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func block(_ block: TranscriptMarkdown.Block) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            if block.listDepth > 0 {
                Text(verbatim: block.listMarker ?? "")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(muted)
                    .frame(minWidth: 15, alignment: .leading)
                    .fixedSize()
            }
            content(block.content)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, CGFloat(max(0, min(block.listDepth - 1, 4))) * 12 + (block.quoted ? 9 : 0))
        .overlay(alignment: .leading) {
            if block.quoted {
                RoundedRectangle(cornerRadius: 1).fill(rule).frame(width: 2).accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder
    private func content(_ content: TranscriptMarkdown.Block.Content) -> some View {
        switch content {
        case .paragraph(let text):
            prose(text, size: 13)
        case .heading(let level, let text):
            prose(text, size: level <= 2 ? 15 : 13, weight: .semibold)
                .accessibilityAddTraits(.isHeader)
        case .code(let language, let text):
            code(language: language, text: text)
        case .table(let columns, let rows):
            table(columns: columns, rows: rows)
        case .rule:
            separator.padding(.vertical, 3)
        }
    }

    private func prose(_ text: AttributedString, size: CGFloat, weight: Font.Weight = .regular) -> some View {
        Text(text)
            .font(.system(size: size, weight: weight))
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func code(language: String?, text: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let language, !language.isEmpty {
                Text(verbatim: language)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(muted)
                    .lineLimit(1)
                    .padding(.horizontal, 9)
                    .padding(.top, 7)
            }
            Text(verbatim: text)
                .font(.system(size: 11.5, design: .monospaced))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 9)
                .padding(.vertical, 8)
        }
        .background(ink.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
        .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(rule).allowsHitTesting(false) }
    }

    @ViewBuilder
    private func table(columns: [PresentationIntent.TableColumn], rows: [[AttributedString]]) -> some View {
        if columns.count > 2 {
            ScrollView(.horizontal) {
                tableRows(columns: columns, rows: rows, fixedColumns: true)
            }
        } else {
            tableRows(columns: columns, rows: rows, fixedColumns: false)
        }
    }

    private func tableRows(
        columns: [PresentationIntent.TableColumn], rows: [[AttributedString]], fixedColumns: Bool
    ) -> some View {
        VStack(spacing: 0) {
            ForEach(rows.indices, id: \.self) { row in
                if row > 0 { separator }
                HStack(alignment: .top, spacing: 0) {
                    ForEach(columns.indices, id: \.self) { column in
                        let alignment = columns[column].alignment
                        prose(rows[row][column], size: 11.5, weight: row == 0 ? .semibold : .regular)
                            .multilineTextAlignment(alignment == .right ? .trailing : alignment == .center ? .center : .leading)
                            .frame(
                                maxWidth: fixedColumns ? nil : .infinity,
                                alignment: alignment == .right ? .trailing : alignment == .center ? .center : .leading
                            )
                            .frame(width: fixedColumns ? 112 : nil)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 7)
                    }
                }
                .background(row == 0 ? ink.opacity(0.045) : .clear)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(rule).allowsHitTesting(false) }
    }

    private var separator: some View {
        Rectangle().fill(rule).frame(height: 1).accessibilityHidden(true)
    }
}
