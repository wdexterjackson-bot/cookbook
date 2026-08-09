//
//  FakeRecipePrepSummaryService.swift
//  cookbook
//

import Foundation

final class FakeRecipePrepSummaryService: RecipePrepSummaryServicing {
    var isAvailable = true
    var stubbedSummary = "Preheat the oven to 350°F. You'll need a 9x13 pan and a stand mixer."
    var stubbedError: Error?
    private(set) var lastInput: RecipePrepSummaryInput?

    func generateSummary(for input: RecipePrepSummaryInput) async throws -> String {
        lastInput = input
        if let stubbedError {
            throw stubbedError
        }
        guard isAvailable else {
            throw RecipePrepSummaryError.unavailable
        }
        guard !input.ingredientLines.isEmpty || !input.stepLines.isEmpty else {
            throw RecipePrepSummaryError.emptyInput
        }
        return stubbedSummary
    }
}
