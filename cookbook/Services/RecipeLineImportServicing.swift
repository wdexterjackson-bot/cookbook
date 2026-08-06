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
    /// The dish's name, if identifiable — from an explicit "Name:" label or
    /// an unambiguous title-like first line. Nil (never guessed) when not
    /// clearly identifiable.
    var title: String? = nil
    /// Which cookbook chapter this recipe belongs to (e.g. "Desserts"),
    /// from an explicit "Section:" label — matched against the target
    /// cookbook's existing chapters by the caller, not resolved here. Nil
    /// when not clearly identifiable.
    var chapterName: String? = nil
    var ingredients: [ParsedIngredientLine]
    var steps: [String]
    /// Trailing commentary distinct from the numbered/imperative cooking
    /// steps — serving info, substitution tips, etc. From an explicit
    /// "Notes:" label, or inferred as non-instructional text following the
    /// last real step. Nil when there's nothing like that to separate out.
    var notes: String? = nil
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
