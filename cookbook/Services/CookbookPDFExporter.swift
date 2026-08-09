//
//  CookbookPDFExporter.swift
//  cookbook
//
//  Renders a personal cookbook's recipes into a single PDF from the
//  Administrator screen's "Export Cookbook to PDF" action — one recipe
//  per page (chapter order, then alphabetically within a chapter, then
//  unfiled recipes last), in the same Name:/By:/Section:/Ingredients/
//  Directions layout Recipe_Import_Format.md documents for bulk import,
//  since that's the reference format this was asked to match. Deliberately
//  omits photos (text-only export) and the Notes section.
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

        writer.draw(labelValueLine(label: "Name: ", value: recipe.title), spacingAfter: 2)
        writer.draw(NSAttributedString(string: recipe.id.uuidString, attributes: idAttributes), spacingAfter: 10)

        if let author = recipe.authorLineage, !author.isEmpty {
            writer.draw(labelValueLine(label: "By: ", value: author), spacingAfter: 10)
        }

        if let sectionTitle, !sectionTitle.isEmpty {
            writer.draw(labelValueLine(label: "Section: ", value: sectionTitle), spacingAfter: 14)
        }

        let ingredientSections = recipe.ingredientSections.sorted { $0.sortOrder < $1.sortOrder }
        if !ingredientSections.isEmpty {
            writer.draw(NSAttributedString(string: "Ingredients", attributes: headingAttributes), spacingAfter: 8)
            for section in ingredientSections {
                if let heading = section.heading, !heading.isEmpty {
                    writer.draw(NSAttributedString(string: heading, attributes: subheadingAttributes), spacingAfter: 4)
                }
                for ingredient in section.ingredients.sorted(by: { $0.sortOrder < $1.sortOrder }) {
                    writer.draw(NSAttributedString(string: ingredient.displayText, attributes: bodyAttributes), spacingAfter: 4)
                }
            }
            writer.addGap(10)
        }

        let stepSections = recipe.stepSections.sorted { $0.sortOrder < $1.sortOrder }
        if !stepSections.isEmpty {
            writer.draw(NSAttributedString(string: "Directions", attributes: headingAttributes), spacingAfter: 8)
            var stepNumber = 1
            for section in stepSections {
                if let heading = section.heading, !heading.isEmpty {
                    writer.draw(NSAttributedString(string: heading, attributes: subheadingAttributes), spacingAfter: 4)
                }
                for step in section.steps.sorted(by: { $0.sortOrder < $1.sortOrder }) {
                    writer.draw(NSAttributedString(string: "\(stepNumber). \(step.text)", attributes: bodyAttributes), spacingAfter: 6)
                    stepNumber += 1
                }
            }
        }
    }

    private static func labelValueLine(label: String, value: String) -> NSAttributedString {
        let result = NSMutableAttributedString(string: label, attributes: boldAttributes)
        result.append(NSAttributedString(string: value, attributes: bodyAttributes))
        return result
    }

    // MARK: - Styles

    private static func ctFont(size: CGFloat, bold: Bool = false) -> CTFont {
        let base = CTFontCreateUIFontForLanguage(.system, size, nil) ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
        guard bold else { return base }
        return CTFontCreateCopyWithSymbolicTraits(base, size, nil, .traitBold, .traitBold) ?? base
    }

    private static let blackColor = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
    private static let grayColor = CGColor(red: 0.45, green: 0.45, blue: 0.45, alpha: 1)
    private static let blueColor = CGColor(red: 0.16, green: 0.38, blue: 0.68, alpha: 1)

    private static let bodyAttributes: [NSAttributedString.Key: Any] = [
        kCTFontAttributeName as NSAttributedString.Key: ctFont(size: 12),
        kCTForegroundColorAttributeName as NSAttributedString.Key: blackColor,
    ]
    private static let boldAttributes: [NSAttributedString.Key: Any] = [
        kCTFontAttributeName as NSAttributedString.Key: ctFont(size: 12, bold: true),
        kCTForegroundColorAttributeName as NSAttributedString.Key: blackColor,
    ]
    private static let idAttributes: [NSAttributedString.Key: Any] = [
        kCTFontAttributeName as NSAttributedString.Key: ctFont(size: 9),
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
    }
}
