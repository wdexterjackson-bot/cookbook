//
//  RecipeFileTextExtractor.swift
//  cookbook
//
//  Pulls plain text out of a file picked for bulk recipe import. Plain
//  text files are read directly; PDFs have their text extracted page by
//  page via PDFKit and joined into one continuous string — a recipe in
//  the source document can span a page break, and
//  RecipeFileImportCoordinator's "Name:"-prefix splitting only works
//  correctly against one continuous string, not per-page fragments.
//

import Foundation
import PDFKit

enum RecipeFileTextExtractionError: Error, LocalizedError {
    case unreadable
    case emptyPDFText

    var errorDescription: String? {
        switch self {
        case .unreadable:
            return "Couldn't read that file."
        case .emptyPDFText:
            return "Couldn't find any text in that PDF — it may be a scanned image rather than real, selectable text."
        }
    }
}

enum RecipeFileTextExtractor {
    static func extractText(from url: URL) throws -> String {
        if url.pathExtension.lowercased() == "pdf" {
            return try extractPDFText(from: url)
        }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw RecipeFileTextExtractionError.unreadable
        }
        return text
    }

    private static func extractPDFText(from url: URL) throws -> String {
        guard let document = PDFDocument(url: url) else {
            throw RecipeFileTextExtractionError.unreadable
        }
        var pageTexts: [String] = []
        for index in 0..<document.pageCount {
            if let pageText = document.page(at: index)?.string {
                pageTexts.append(pageText)
            }
        }
        let combined = pageTexts.joined(separator: "\n")
        guard !combined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RecipeFileTextExtractionError.emptyPDFText
        }
        return combined
    }
}
