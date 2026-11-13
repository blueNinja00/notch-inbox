import SwiftUI

/// Words from the assistant or an agent, drawn from their Markdown: headings, lists, tables,
/// quotes and code, with the bold, italics, code and links inside them. The chat, the team
/// chat and agents' reports all draw their words with this. (It holds only plain values,
/// so SwiftUI can tell when nothing has changed and leave it as it is.)
struct MarkdownBlocks: View {
    let text: String
    var size: CGFloat = 12.5
    var colour: Color = Theme.body
    /// Whether each line takes the whole width (a report) or only what it needs (a bubble).
    var fills = true
    /// For a long report: only the part on screen is laid out.
    var lazily = false

    var body: some View {
        let blocks = AgentReport.blocks(text)

        if lazily {
            LazyVStack(alignment: .leading, spacing: 3) {
                ForEach(blocks) { block in
                    MarkdownBlock(block: block, size: size, colour: colour, fills: fills)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(blocks) { block in
                    MarkdownBlock(block: block, size: size, colour: colour, fills: fills)
                }
            }
        }
    }
}

/// One piece of it: a heading, a paragraph, a line of a list, a table, some code.
struct MarkdownBlock: View {
    let block: AgentReport.Block
    let size: CGFloat
    let colour: Color
    let fills: Bool

    var body: some View {
        switch block.kind {
        case .heading(let level):
            AgentWords(text: block.text, size: MarkdownBlock.headingSize(level, base: size), weight: .bold, colour: Theme.text, fills: fills)
                .padding(.top, 5)
        case .bullet(let indent):
            AgentListLine(mark: "•", text: block.text, indent: indent, size: size, colour: colour, fills: fills)
        case .numbered(let number, let indent):
            AgentListLine(mark: number, text: block.text, indent: indent, size: size, colour: colour, fills: fills)
        case .quote:
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Theme.tertiary)
                    .frame(width: 2)
                AgentWords(text: block.text, size: size, colour: Theme.secondary, fills: fills)
            }
        case .code:
            MarkdownCode(text: block.text, size: size, fills: fills)
        case .table(let rows):
            MarkdownTable(rows: rows, size: size, colour: colour, fills: fills)
        case .rule:
            Rectangle()
                .fill(Theme.hairline)
                .frame(height: 1)
                .padding(.vertical, 4)
        case .paragraph:
            AgentWords(text: block.text, size: size, colour: colour, fills: fills)
        case .gap:
            Color.clear
                .frame(height: 4)
        }
    }

    /// A heading is a little bigger than the words under it, the more so the higher it is.
    static func headingSize(_ level: Int, base: CGFloat) -> CGFloat {
        if level <= 1 {
            return base + 2.5
        }
        return level == 2 ? base + 1.5 : base + 0.5
    }
}

/// A block of code, kept as it was written.
struct MarkdownCode: View {
    let text: String
    let size: CGFloat
    let fills: Bool

    var body: some View {
        Text(text.isEmpty ? " " : text)
            .font(.system(size: size - 1, design: .monospaced))
            .foregroundStyle(Theme.text2)
            .lineSpacing(2)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: fills ? .infinity : nil, alignment: .leading)
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black.opacity(0.3)))
    }
}

/// A table, with its columns lined up and a line under its header.
struct MarkdownTable: View {
    let rows: [AgentReport.TableRow]
    let size: CGFloat
    let colour: Color
    let fills: Bool

    var body: some View {
        Grid(alignment: .topLeading, horizontalSpacing: 14, verticalSpacing: 6) {
            ForEach(rows) { row in
                GridRow {
                    ForEach(row.cells) { cell in
                        AgentWords(text: cell.text, size: size - 0.5, weight: row.isHeader ? .semibold : .regular,
                                   colour: row.isHeader ? Theme.text2 : colour, fills: fills)
                    }
                }
                if row.isHeader {
                    Rectangle()
                        .fill(Theme.hairline)
                        .frame(height: 1)
                        .gridCellUnsizedAxes(.horizontal)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
        .padding(.vertical, 2)
    }
}

/// A bullet or a numbered line, hanging from its mark.
struct AgentListLine: View {
    let mark: String
    let text: String
    let indent: Int
    var size: CGFloat = 12.5
    var colour: Color = Theme.body
    var fills = true

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(mark)
                .font(.system(size: size, weight: .medium).monospacedDigit())
                .foregroundStyle(Theme.tertiary)
            AgentWords(text: text, size: size, colour: colour, fills: fills)
        }
        .padding(.leading, CGFloat(indent) * 14)
    }
}

/// A line of words, with its bold, italics, code and links drawn.
struct AgentWords: View {
    let text: String
    var size: CGFloat = 12.5
    var weight: Font.Weight = .regular
    var colour: Color = Theme.body
    var fills = true

    var body: some View {
        Text(ChatBubble.formatted(text))
            .font(.system(size: size, weight: weight))
            .foregroundStyle(colour)
            .lineSpacing(2.5)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: fills ? .infinity : nil, alignment: .leading)
    }
}
