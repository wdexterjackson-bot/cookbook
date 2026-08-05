//
//  RecipeLineImportServicing.swift
//  cookbook
//
//  The seam for AI-assisted paste-to-import: FoundationModelsLineImportService
//  is the real, on-device adapter; FakeRecipeLineImportService backs tests.
//  Result types here are plain (no FoundationModels import needed outside
//  the real adapter), mirroring how MealSearchServicing keeps API-specific
//  DTOs private to their own adapter files.
//

import Foundation

struct ParsedIngredientLine: Equatable {
    var name: String
    var quantity: Double?
    var unit: String?
}

struct ParsedRecipeLines: Equatable {
    var ingredients: [ParsedIngredientLine]
    var steps: [String]
}

enum RecipeLineImportError: Error, Equatable {
    case unavailable
    case emptyInput
    case parsingFailed
}

protocol RecipeLineImportServicing {
    /// Whether on-device AI can actually run right now — gated by device
    /// eligibility, the Apple Intelligence setting, and model readiness,
    /// not just OS version. The UI checks this before offering Import.
    var isAvailable: Bool { get }
    func parseLines(from text: String) async throws -> ParsedRecipeLines
}
