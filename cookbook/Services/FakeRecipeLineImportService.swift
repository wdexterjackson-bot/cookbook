//
//  FakeRecipeLineImportService.swift
//  cookbook
//

import Foundation

final class FakeRecipeLineImportService: RecipeLineImportServicing {
    var isAvailable = true
    var stubbedResult = ParsedRecipeLines(ingredients: [], steps: [])
    var stubbedError: Error?
    private(set) var lastParsedText: String?

    func parseLines(from text: String) async throws -> ParsedRecipeLines {
        lastParsedText = text
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
        return stubbedResult
    }
}
