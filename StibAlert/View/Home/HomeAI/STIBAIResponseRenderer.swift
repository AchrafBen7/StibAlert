import SwiftUI

struct STIBAIResponseRenderer: View {
    let text: String

    private var blocks: [STIBAIResponseBlock] {
        STIBAIResponseBlock.parse(text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(blocks) { block in
                switch block.kind {
                case .heading(let title):
                    Text(title.uppercased())
                        .font(DS.Font.monoLarge)
                        .tracking(1.6)
                        .foregroundStyle(DS.Color.ink)
                        .padding(.top, block.isFirst ? 0 : 6)

                case .paragraph(let value):
                    STIBAIInlineLine(text: value)

                case .bullet(let value):
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(DS.Color.inkMute)
                            .frame(width: 5, height: 5)
                            .foregroundStyle(DS.Color.inkMute)
                            .padding(.top, 9)
                        STIBAIInlineLine(text: value)
                    }
                }
            }
        }
    }
}

private struct STIBAIInlineLine: View {
    let text: String

    private var tokens: [STIBAIInlineToken] {
        STIBAIInlineToken.parse(text)
    }

    var body: some View {
        STIBAIFlowLayout(horizontalSpacing: 6, verticalSpacing: 7) {
            ForEach(tokens) { token in
                switch token.kind {
                case .text(let value, let isStrong):
                    Text(value)
                        .font(DS.Font.body)
                        .fontWeight(isStrong ? .bold : .regular)
                        .foregroundStyle(DS.Color.ink)
                        .fixedSize(horizontal: true, vertical: false)
                case .line(let line):
                    LineBadge(line: line, size: .sm)
                        .alignmentGuide(.firstTextBaseline) { dimensions in
                            dimensions[VerticalAlignment.center]
                        }
                }
            }
        }
    }
}

private struct STIBAIResponseBlock: Identifiable {
    enum Kind {
        case heading(String)
        case paragraph(String)
        case bullet(String)
    }

    let id = UUID()
    let kind: Kind
    let isFirst: Bool

    static func parse(_ text: String) -> [STIBAIResponseBlock] {
        let prepared = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: #"(?<!\n)(#{2,3}\s+)"#, with: "\n$1", options: .regularExpression)
            .replacingOccurrences(of: #"(?<!\n)([-•]\s+\[\[L:)"#, with: "\n$1", options: .regularExpression)

        var output: [STIBAIResponseBlock] = []
        for rawLine in prepared.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            let kind: Kind
            if line.hasPrefix("### ") {
                kind = .heading(String(line.dropFirst(4)).trimmedAIText)
            } else if line.hasPrefix("## ") {
                kind = .heading(String(line.dropFirst(3)).trimmedAIText)
            } else if line.hasPrefix("- ") {
                kind = .bullet(String(line.dropFirst(2)).trimmedAIText)
            } else if line.hasPrefix("• ") {
                kind = .bullet(String(line.dropFirst(2)).trimmedAIText)
            } else {
                kind = .paragraph(line.trimmedAIText)
            }

            output.append(STIBAIResponseBlock(kind: kind, isFirst: output.isEmpty))
        }
        return output
    }
}

private struct STIBAIInlineToken: Identifiable {
    enum Kind {
        case text(String, isStrong: Bool)
        case line(String)
    }

    let id = UUID()
    let kind: Kind

    static func parse(_ text: String) -> [STIBAIInlineToken] {
        let nsText = text as NSString
        let regex = try? NSRegularExpression(pattern: #"\[\[L:([A-Za-z0-9]+)\]\]"#)
        let matches = regex?.matches(in: text, range: NSRange(location: 0, length: nsText.length)) ?? []

        guard !matches.isEmpty else {
            var tokens: [STIBAIInlineToken] = []
            appendText(text, to: &tokens)
            return tokens
        }

        var tokens: [STIBAIInlineToken] = []
        var cursor = 0
        for match in matches {
            if match.range.location > cursor {
                let value = nsText.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
                appendText(value, to: &tokens)
            }
            if match.numberOfRanges > 1 {
                let line = nsText.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !line.isEmpty {
                    tokens.append(.init(kind: .line(line)))
                }
            }
            cursor = match.range.location + match.range.length
        }
        if cursor < nsText.length {
            appendText(nsText.substring(from: cursor), to: &tokens)
        }
        return tokens
    }

    private static func appendText(_ value: String, to tokens: inout [STIBAIInlineToken]) {
        let cleaned = value.replacingOccurrences(of: #" {2,}"#, with: " ", options: .regularExpression)
        guard !cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let nsText = cleaned as NSString
        let regex = try? NSRegularExpression(pattern: #"\*\*([^*]+)\*\*"#)
        let matches = regex?.matches(in: cleaned, range: NSRange(location: 0, length: nsText.length)) ?? []

        guard !matches.isEmpty else {
            appendPlainText(cleaned, isStrong: false, to: &tokens)
            return
        }

        var cursor = 0
        for match in matches {
            if match.range.location > cursor {
                appendPlainText(
                    nsText.substring(with: NSRange(location: cursor, length: match.range.location - cursor)),
                    isStrong: false,
                    to: &tokens
                )
            }
            if match.numberOfRanges > 1 {
                appendPlainText(nsText.substring(with: match.range(at: 1)), isStrong: true, to: &tokens)
            }
            cursor = match.range.location + match.range.length
        }
        if cursor < nsText.length {
            appendPlainText(nsText.substring(from: cursor), isStrong: false, to: &tokens)
        }
    }

    private static func appendPlainText(_ value: String, isStrong: Bool, to tokens: inout [STIBAIInlineToken]) {
        let normalized = value
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }

        if isStrong {
            tokens.append(.init(kind: .text(normalized, isStrong: true)))
            return
        }

        let words = normalized.split(separator: " ", omittingEmptySubsequences: true)
        for (index, word) in words.enumerated() {
            let suffix = index == words.count - 1 ? "" : " "
            tokens.append(.init(kind: .text(String(word) + suffix, isStrong: false)))
        }
    }
}

private struct STIBAIFlowLayout: Layout {
    var horizontalSpacing: CGFloat
    var verticalSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 320
        let rows = computeRows(maxWidth: maxWidth, subviews: subviews)
        return CGSize(width: maxWidth, height: rows.last.map { $0.y + $0.height } ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in computeRows(maxWidth: bounds.width, subviews: subviews) {
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: bounds.minX + item.x, y: bounds.minY + row.y),
                    proposal: ProposedViewSize(width: item.size.width, height: item.size.height)
                )
            }
        }
    }

    private func computeRows(maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var currentItems: [Item] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let nextX = currentItems.isEmpty ? 0 : x + horizontalSpacing
            if !currentItems.isEmpty, nextX + size.width > maxWidth {
                rows.append(Row(y: y, height: rowHeight, items: currentItems))
                y += rowHeight + verticalSpacing
                currentItems = []
                x = 0
                rowHeight = 0
            }

            let itemX = currentItems.isEmpty ? 0 : x + horizontalSpacing
            currentItems.append(Item(index: index, x: itemX, size: size))
            x = itemX + size.width
            rowHeight = max(rowHeight, size.height)
        }

        if !currentItems.isEmpty {
            rows.append(Row(y: y, height: rowHeight, items: currentItems))
        }
        return rows
    }

    private struct Row {
        let y: CGFloat
        let height: CGFloat
        let items: [Item]
    }

    private struct Item {
        let index: Int
        let x: CGFloat
        let size: CGSize
    }
}

private extension String {
    var trimmedAIText: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
