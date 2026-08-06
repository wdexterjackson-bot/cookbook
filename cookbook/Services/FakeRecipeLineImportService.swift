//
//  FakeRecipeLineImportService.swift
//  cookbook
//

import Foundation

final class FakeRecipeLineImportService: RecipeLineImportServicing {
    var isAvailable = true
    var stubbedResult = ParsedRecipeLines(ingredients: [], steps: [])
    /// Keyed by the exact input text — takes precedence over
    /// `stubbedResult` when present, so a test driving multiple distinct
    /// inputs (e.g. bulk import's per-chunk calls) can stub a different
    /// result for each one.
    var stubbedResultsByInput: [String: ParsedRecipeLines] = [:]
    /// Keyed by the exact input text — takes precedence over
    /// `stubbedError`, same reasoning as `stubbedResultsByInput`.
    var stubbedErrorsByInput: [String: Error] = [:]
    var stubbedError: Error?
    private(set) var lastParsedText: String?
    private(set) var allParsedTexts: [String] = []

    func parseLines(from text: String) async throws -> ParsedRecipeLines {
        lastParsedText = text
        allParsedTexts.append(text)
        if let error = stubbedErrorsByInput[text] {
            throw error
        }
        if let stubbedError {
            throw stubbedError
        }
        guard isAvailable else {
            throw RecipeLineImportError.unavailable
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw RecipeLineImportError.emptyInput
        }
        return stubbedResultsByInput[text] ?? stubbedResult
    }
}
