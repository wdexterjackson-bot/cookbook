//
//  RecipePrepSummaryServicing.swift
//  cookbook
//
//  The seam for Cooking Mode's prep-review page: given a recipe's
//  ingredients and steps, generate a short natural-language summary of what
//  to do before starting to cook — equipment needed, whether to preheat the
//  oven, etc. FoundationModelsPrepSummaryService is the real, on-device
//  adapter; FakeRecipePrepSummaryService backs tests. Input is plain data
//  (not a SwiftData Recipe) so this seam doesn't need a SwiftData import,
//  mirroring RecipeLineImportServicing's same reasoning.
//

import Foundation

struct RecipePrepSummaryInput: Equatable {
    var title: String
    var ingredientLines: [String]
    var stepLines: [String]
}

enum RecipePrepSummaryError: Error, Equatable {
    case unavailable
    case emptyInput
    case generationFailed
}

protocol RecipePrepSummaryServicing {
    /// Whether on-device AI can actually run right now — same runtime
    /// eligibility/setting/readiness check as RecipeLineImportServicing,
    /// not just an OS-version gate.
    var isAvailable: Bool { get }
    func generateSummary(for input: RecipePrepSummaryInput) async throws -> String
}
