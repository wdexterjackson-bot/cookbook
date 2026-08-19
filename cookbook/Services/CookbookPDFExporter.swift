//
//  CookbookPDFExporter.swift
//  cookbook
//
//  Renders a personal cookbook's recipes into a single PDF from the
//  Administrator screen's "Export Cookbook to PDF" action — one recipe
//  per page (chapter order, then alphabetically within a chapter, then
//  unfiled recipes last). Layout/styling matches Sample.pdf (bundled in
//  the app, linked from the Administrator screen) exactly, since that's
//  also the format Recipe_Import_Format.md documents for bulk import —
//  Name/By/Section/Ingredients/Directions/Notes/Videos, in that order,
//  every heading always shown even when its section is empty. Deliberately
//  omits photos (text-only export).
//
//  Pure CoreGraphics + CoreText rather than UIGraphicsPDFRenderer/AppKit
//  printing APIs, so the same code runs unchanged on iOS, macOS, and
//  visionOS — CTFont/CGColor attribute keys read identically on every
//  platform, unlike UIFont/NSFont or UIColor/NSColor.
//

import Foundation
import CoreGraphics
import CoreText

enum CookbookPDFExporter {
    private static let pageWidth: CGFloat = 612   // US Letter, 72pt/in
    private static let pageHeight: CGFloat = 792
    private static let margin: CGFloat = 54
    private static var contentWidth: CGFloat { pageWidth - margin * 2 }

    static func generatePDF(for cookbook: Cookbook, recipes: [Recipe]) -> Data {
        let mutableData = NSMutableData()
        guard let consumer = CGDataConsumer(data: mutableData as CFMutableData) else { return Data() }
        var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return Data() }

        let writer = PageWriter(context: context)
        for (recipe, sectionTitle) in orderedForExport(recipes: recipes, sections: cookbook.sections) {
            draw(recipe, sectionTitle: sectionTitle, writer: writer)
        }
        writer.finish()
        context.closePDF()
        return mutableData as Data
    }

    // MARK: - Ordering

    private static func byTitle(_ lhs: Recipe, _ rhs: Recipe) -> Bool {
        lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }

    private static func orderedForExport(recipes: [Recipe], sections: [CookbookSection]) -> [(recipe: Recipe, sectionTitle: String?)] {
        var result: [(recipe: Recipe, sectionTitle: String?)] = []
        let sortedSections = sections.sorted { $0.sortOrder < $1.sortOrder }
        for section in sortedSections {
            let inSection: [Recipe] = recipes.filter { $0.sectionID == section.id }.sorted(by: byTitle)
            for recipe in inSection {
                result.append((recipe: recipe, sectionTitle: section.title))
            }
        }
        let knownSectionIDs = Set(sortedSections.map(\.id))
        let unfiled: [Recipe] = recipes.filter { recipe in
            guard let sectionID = recipe.sectionID else { return true }
            return !knownSectionIDs.contains(sectionID)
        }.sorted(by: byTitle)
        for recipe in unfiled {
            result.append((recipe: recipe, sectionTitle: nil))
        }
        return result
    }

    // MARK: - Drawing

    private static func draw(_ recipe: Recipe, sectionTitle: String?, writer: PageWriter) {
        writer.beginNewPage()

        writer.draw(NSAttributedString(string: "Name: \(recipe.title)", attributes: headingAttributes), spacingAfter: 3)

        if let author = recipe.authorLineage, !author.isEmpty {
            writer.draw(NSAttributedString(string: "By: \(author)", attributes: grayItalicAttributes), spacingAfter: 3)
        }

        if let sectionTitle, !sectionTitle.isEmpty {
            writer.draw(NSAttributedString(string: "Section: \(sectionTitle)", attributes: grayItalicAttributes), spacingAfter: 3)
        }
        writer.addGap(8)

        writer.draw(NSAttributedString(string: "Ingredients:", attributes: headingAttributes), spacingAfter: 8)
        for section in recipe.ingredientSections.sorted(by: { $0.sortOrder < $1.sortOrder }) {
            if let heading = section.heading, !heading.isEmpty {
                writer.draw(NSAttributedString(string: heading, attributes: subheadingAttributes), spacingAfter: 4)
            }
            for ingredient in section.ingredients.sorted(by: { $0.sortOrder < $1.sortOrder }) {
                writer.draw(NSAttributedString(string: "•  \(ingredient.displayText)", attributes: bodyAttributes), spacingAfter: 4)
            }
        }
        writer.addGap(10)

        writer.draw(NSAttributedString(string: "Directions:", attributes: headingAttributes), spacingAfter: 8)
        var stepNumber = 1
        for section in recipe.stepSections.sorted(by: { $0.sortOrder < $1.sortOrder }) {
            if let heading = section.heading, !heading.isEmpty {
                writer.draw(NSAttributedString(string: heading, attributes: subheadingAttributes), spacingAfter: 4)
            }
            for step in section.steps.sorted(by: { $0.sortOrder < $1.sortOrder }) {
                writer.draw(NSAttributedString(string: "\(stepNumber). \(step.text)", attributes: bodyAttributes), spacingAfter: 6)
                stepNumber += 1
            }
        }
        writer.addGap(10)

        writer.draw(NSAttributedString(string: "Notes:", attributes: headingAttributes), spacingAfter: 6)
        let trimmedNotes = recipe.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedNotes.isEmpty {
            writer.draw(NSAttributedString(string: trimmedNotes, attributes: bodyAttributes), spacingAfter: 6)
        }
        writer.addGap(10)

        writer.draw(NSAttributedString(string: "Videos:", attributes: headingAttributes), spacingAfter: 6)
        for videoURL in recipe.videoURLs {
            writer.draw(NSAttributedString(string: videoURL, attributes: bodyAttributes), spacingAfter: 4)
        }
        writer.addGap(14)

        writer.drawDivider()
    }

    // MARK: - Styles

    private static func ctFont(size: CGFloat, bold: Bool = false, italic: Bool = false) -> CTFont {
        let base = CTFontCreateUIFontForLanguage(.system, size, nil) ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
        var traits: CTFontSymbolicTraits = []
        if bold { traits.insert(.traitBold) }
        if italic { traits.insert(.traitItalic) }
        guard !traits.isEmpty else { return base }
        return CTFontCreateCopyWithSymbolicTraits(base, size, nil, traits, traits) ?? base
    }

    private static let blackColor = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
    private static let grayColor = CGColor(red: 0.45, green: 0.45, blue: 0.45, alpha: 1)
    private static let blueColor = CGColor(red: 0.16, green: 0.38, blue: 0.68, alpha: 1)
    private static let dividerColor = CGColor(red: 0.16, green: 0.38, blue: 0.68, alpha: 0.4)

    private static let bodyAttributes: [NSAttributedString.Key: Any] = [
        kCTFontAttributeName as NSAttributedString.Key: ctFont(size: 12),
        kCTForegroundColorAttributeName as NSAttributedString.Key: blackColor,
    ]
    private static let grayItalicAttributes: [NSAttributedString.Key: Any] = [
        kCTFontAttributeName as NSAttributedString.Key: ctFont(size: 11, italic: true),
        kCTForegroundColorAttributeName as NSAttributedString.Key: grayColor,
    ]
    private static let headingAttributes: [NSAttributedString.Key: Any] = [
        kCTFontAttributeName as NSAttributedString.Key: ctFont(size: 17),
        kCTForegroundColorAttributeName as NSAttributedString.Key: blueColor,
    ]
    private static let subheadingAttributes: [NSAttributedString.Key: Any] = [
        kCTFontAttributeName as NSAttributedString.Key: ctFont(size: 12, bold: true),
        kCTForegroundColorAttributeName as NSAttributedString.Key: blackColor,
    ]

    /// Owns a running cursor down one PDF page, opening a new page
    /// whenever the next block wouldn't fit in the remaining space —
    /// block-level pagination (never splits a single ingredient/step line
    /// across pages), which is sufficient since Recipe_Import_Format-style
    /// recipes are made of short, discrete lines rather than long prose.
    private final class PageWriter {
        private let context: CGContext
        private var cursorY: CGFloat = 0
        private var pageIsOpen = false

        init(context: CGContext) {
            self.context = context
        }

        func beginNewPage() {
            if pageIsOpen { context.endPDFPage() }
            context.beginPDFPage(nil)
            pageIsOpen = true
            cursorY = pageHeight - margin
        }

        func finish() {
            if pageIsOpen { context.endPDFPage() }
            pageIsOpen = false
        }

        func addGap(_ amount: CGFloat) {
            cursorY -= amount
        }

        func draw(_ attributedString: NSAttributedString, spacingAfter: CGFloat) {
            let framesetter = CTFramesetterCreateWithAttributedString(attributedString)
            let constraint = CGSize(width: contentWidth, height: .greatestFiniteMagnitude)
            let fitSize = CTFramesetterSuggestFrameSizeWithConstraints(framesetter, CFRange(location: 0, length: 0), nil, constraint, nil)

            if !pageIsOpen || cursorY - fitSize.height < margin {
                beginNewPage()
            }

            let originY = cursorY - fitSize.height
            let path = CGPath(rect: CGRect(x: margin, y: originY, width: contentWidth, height: fitSize.height), transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
            CTFrameDraw(frame, context)
            cursorY = originY - spacingAfter
        }

        /// A thin horizontal rule spanning the content width, closing out
        /// one recipe's page — matches Sample.pdf's divider between the
        /// end of a recipe's content and the page's remaining whitespace.
        func drawDivider() {
            let lineWidth: CGFloat = 1
            if !pageIsOpen || cursorY - lineWidth < margin {
                beginNewPage()
            }
            context.saveGState()
            context.setStrokeColor(dividerColor)
            context.setLineWidth(lineWidth)
            context.move(to: CGPoint(x: margin, y: cursorY))
            context.addLine(to: CGPoint(x: margin + contentWidth, y: cursorY))
            context.strokePath()
            context.restoreGState()
            cursorY -= lineWidth
        }
    }
}
