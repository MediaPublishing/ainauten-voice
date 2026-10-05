import AppKit

@main
enum ReportRenderingChecks {
    static func main() throws {
        let rendered = ReportMarkdown.render("""
        # Titel

        Ein **fetter** `Code` und [Link](https://example.com).

        - Eins
        - Zwei

        1. Erster
        2. Zweiter

        | Name | Wert |
        |---|---|
        | Test | **42** |
        """)
        func require(_ value: @autoclosure () -> Bool, _ message: String) {
            guard value() else { fatalError(message) }
        }
        func font(_ term: String) -> NSFont {
            rendered.attribute(.font, at: (rendered.string as NSString).range(of: term).location, effectiveRange: nil) as! NSFont
        }
        require(rendered.string == "Titel\nEin fetter Code und Link.\n•\tEins\n•\tZwei\n1.\tErster\n2.\tZweiter\nName\nWert\nTest\n42\n", "Markdown content or block boundaries lost")
        require(font("Titel").pointSize == 22, "Heading style missing")
        require(NSFontManager.shared.traits(of: font("fetter")).contains(.boldFontMask), "Bold style missing")
        require(font("Code").isFixedPitch, "Code must be monospaced")
        let linkIndex = (rendered.string as NSString).range(of: "Link").location
        require((rendered.attribute(.link, at: linkIndex, effectiveRange: nil) as? URL)?.absoluteString == "https://example.com", "Link lost")
        var cells: [NSTextTableBlock] = []
        rendered.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: rendered.length)) { value, _, _ in
            if let cell = (value as? NSParagraphStyle)?.textBlocks.first as? NSTextTableBlock { cells.append(cell) }
        }
        require(cells.count == 4 && cells.allSatisfy { $0.table.numberOfColumns == 2 }, "Table cells lost")
        require(cells.last?.startingRow == 1 && cells.last?.startingColumn == 1, "Wrong table coordinates")
        require(cells.first?.table === cells.last?.table, "Cells no longer share a table")
        let report = try String(contentsOfFile: "docs/verification-report.md", encoding: .utf8)
        let full = ReportMarkdown.render(report)
        require(full.string.contains("AInauten Voice: Prüfbericht") && full.string.contains("Sprachrückmeldung und unpersönlicher Probetest"), "Report truncated")
        require(!full.string.contains("## ") && !full.string.contains("**"), "Unrendered headings or bold markers")
        require(ReportMarkdown.render("").length == 0, "Empty report should remain empty")
        print("11 report rendering checks passed; full report \(full.length) characters")
    }
}
