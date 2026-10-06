import AppKit
import SwiftUI
import VoiceWisprCore

/// Uses Foundation's Markdown parser and AppKit's selectable rich text, entirely locally.
struct ReportView: NSViewRepresentable {
    let markdown: String
    @Environment(\.colorScheme) private var colorScheme

    final class Coordinator { var markdown: String?; var scheme: ColorScheme? }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let text = NSTextView(frame: scroll.bounds)
        text.isEditable = false
        text.isSelectable = true
        text.drawsBackground = false
        text.isRichText = true
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true
        text.textContainer?.containerSize = NSSize(width: scroll.bounds.width, height: CGFloat.greatestFiniteMagnitude)
        text.textContainerInset = NSSize(width: 0, height: 8)
        text.textContainer?.lineFragmentPadding = 0
        text.minSize = .zero
        text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        text.setAccessibilityLabel(L10n.text("report.accessibility"))
        scroll.documentView = text
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard context.coordinator.markdown != markdown || context.coordinator.scheme != colorScheme,
              let text = scroll.documentView as? NSTextView else { return }
        context.coordinator.markdown = markdown
        context.coordinator.scheme = colorScheme
        // Model updates must not reset selection or scroll position in an unchanged report.
        text.textStorage?.setAttributedString(ReportMarkdown.render(markdown))
    }
}

enum ReportMarkdown {
    static func render(_ markdown: String) -> NSAttributedString {
        guard let parsed = try? AttributedString(markdown: markdown) else {
            return NSAttributedString(string: markdown, attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.labelColor])
        }
        let output = NSMutableAttributedString(string: "")
        var blockID: Int?
        var paragraph = NSMutableParagraphStyle()
        var baseFont = NSFont.systemFont(ofSize: 13)
        var tables: [Int: NSTextTable] = [:]

        for run in parsed.runs {
            let components = run.presentationIntent?.components ?? []
            let id = components.first?.identity ?? 0
            if id != blockID {
                if output.length > 0 { output.append(NSAttributedString(string: "\n", attributes: [.paragraphStyle: paragraph])) }
                blockID = id
                paragraph = NSMutableParagraphStyle()
                paragraph.lineSpacing = 3
                paragraph.paragraphSpacing = 12
                baseFont = .systemFont(ofSize: 13)
                var prefix = ""
                for component in components {
                    switch component.kind {
                    case .header(let level):
                        baseFont = .systemFont(ofSize: level == 1 ? 22 : level == 2 ? 17 : 14, weight: .semibold)
                        paragraph.paragraphSpacingBefore = 12
                    case .listItem(let ordinal):
                        prefix = components.contains(where: { $0.kind == .orderedList }) ? "\(ordinal).\t" : "•\t"
                        paragraph.headIndent = 18
                        paragraph.tabStops = [NSTextTab(textAlignment: .left, location: 18)]
                        paragraph.paragraphSpacing = 6
                    case .codeBlock:
                        baseFont = .monospacedSystemFont(ofSize: 12, weight: .regular)
                    case .blockQuote:
                        paragraph.headIndent = 16
                        paragraph.firstLineHeadIndent = 16
                    case .table(let columns):
                        let table = tables[component.identity] ?? NSTextTable()
                        table.numberOfColumns = columns.count
                        table.layoutAlgorithm = .automaticLayoutAlgorithm
                        table.collapsesBorders = true
                        table.setContentWidth(100, type: .percentageValueType)
                        tables[component.identity] = table
                        var row = 0, column = 0, header = false
                        for cellComponent in components {
                            if case .tableRow(let index) = cellComponent.kind { row = index }
                            if case .tableCell(let index) = cellComponent.kind { column = index }
                            if case .tableHeaderRow = cellComponent.kind { header = true }
                        }
                        let cell = NSTextTableBlock(table: table, startingRow: row, rowSpan: 1, startingColumn: column, columnSpan: 1)
                        cell.setWidth(6, type: .absoluteValueType, for: .padding)
                        cell.setWidth(0.5, type: .absoluteValueType, for: .border)
                        cell.setBorderColor(.separatorColor)
                        cell.verticalAlignment = .topAlignment
                        if header { cell.backgroundColor = .quaternaryLabelColor }
                        paragraph.textBlocks = [cell]
                        paragraph.paragraphSpacing = 0
                        paragraph.lineSpacing = 2
                        baseFont = .systemFont(ofSize: 12, weight: header ? .semibold : .regular)
                    default: break
                    }
                }
                if !prefix.isEmpty { output.append(NSAttributedString(string: prefix, attributes: [.font: baseFont, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph])) }
            }
            var font = baseFont
            let inline = run.inlinePresentationIntent ?? []
            if inline.contains(.code) { font = .monospacedSystemFont(ofSize: 12, weight: .regular) }
            if inline.contains(.stronglyEmphasized) { font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
            if inline.contains(.emphasized) { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
            let part = NSMutableAttributedString(attributedString: NSAttributedString(AttributedString(parsed[run.range])))
            let range = NSRange(location: 0, length: part.length)
            part.addAttributes([.font: font, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph], range: range)
            if inline.contains(.strikethrough) { part.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range) }
            if run.link != nil { part.addAttribute(.foregroundColor, value: NSColor.linkColor, range: range) }
            output.append(part)
        }
        if output.length > 0 { output.append(NSAttributedString(string: "\n", attributes: [.paragraphStyle: paragraph])) }
        return output
    }
}
