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
    static func extractText(
        from url: URL,
        onPDFPageProgress: @escaping @Sendable @MainActor (Int, Int) -> Void = { _, _ in }
    ) async throws -> String {
        if url.pathExtension.lowercased() == "pdf" {
            return try await extractPDFText(from: url, onProgress: onPDFPageProgress)
        }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw RecipeFileTextExtractionError.unreadable
        }
        return text
    }

    /// Runs off the main thread (Task.detached) so a large PDF's
    /// page-by-page loop never blocks the UI — calling this synchronously
    /// inline on the main actor was the previous behavior and actively
    /// froze the screen for big files. `onProgress` is invoked once per
    /// page, hopping back to the main actor just for that call.
    private static func extractPDFText(
        from url: URL,
        onProgress: @escaping @Sendable @MainActor (Int, Int) -> Void
    ) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            guard let document = PDFDocument(url: url) else {
                throw RecipeFileTextExtractionError.unreadable
            }
            let pageCount = document.pageCount
            // Reported before the loop starts — see the matching comment
            // in RecipeFileImportCoordinator.parseRecipes for why waiting
            // for the first per-item callback leaves the total unknown
            // for the whole first item.
            await onProgress(0, pageCount)
            var pageTexts: [String] = []
            for index in 0..<pageCount {
                if let pageText = document.page(at: index)?.string {
                    pageTexts.append(pageText)
                }
                await onProgress(index + 1, pageCount)
            }
            let combined = pageTexts.joined(separator: "\n")
            guard !combined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw RecipeFileTextExtractionError.emptyPDFText
            }
            return combined
        }.value
    }
}
