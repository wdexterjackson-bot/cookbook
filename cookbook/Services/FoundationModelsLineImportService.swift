//
//  FoundationModelsLineImportService.swift
//  cookbook
//
//  Uses Apple's on-device FoundationModels framework (confirmed present in
//  this SDK, iOS 26.0+ — our deployment target is already 26.5) to split a
//  pasted block of recipe text into structured ingredients and steps in
//  one pass. Runs fully on-device: no network call, no API key, no cost —
//  matches this app's local-first bias everywhere else. isAvailable checks
//  SystemLanguageModel at runtime, since Apple Intelligence availability is
//  gated by device eligibility/region/user setting, not just OS version.
//
//  Known gap: on-device model *inference* may not actually execute inside
//  the iOS Simulator (it typically needs the real Neural Engine) — this
//  has been reviewed against the SDK's public interface but not proven to
//  produce a real model response in this environment.
//

import Foundation
import FoundationModels

final class FoundationModelsLineImportService: RecipeLineImportServicing {
    var isAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }

    func parseLines(from text: String) async throws -> ParsedRecipeLines {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw RecipeLineImportError.emptyInput
        }
        guard isAvailable else {
            throw RecipeLineImportError.unavailable
        }

        let session = LanguageModelSession {
            """
            You extract recipe ingredients and instruction steps from pasted,
            possibly messy text. Classify each line as either an ingredient or
            an instruction step. For ingredients, separate the quantity (a
            plain number — convert fractions like "1/2" to 0.5) and unit
            (e.g. cup, tbsp, oz, g) from the ingredient name whenever
            possible; omit quantity or unit for a line that doesn't clearly
            have one (e.g. "salt to taste"). Preserve the original order
            within each list.
            """
        }

        do {
            let response = try await session.respond(to: trimmed, generating: GeneratedRecipeLines.self)
            let content = response.content
            let ingredients = content.ingredients.map {
                ParsedIngredientLine(name: $0.name, quantity: $0.quantity, unit: $0.unit)
            }
            return ParsedRecipeLines(ingredients: ingredients, steps: content.steps)
        } catch {
            throw RecipeLineImportError.parsingFailed
        }
    }
}

@Generable
private struct GeneratedRecipeLines {
    @Generable
    struct GeneratedIngredient {
        var name: String
        var quantity: Double?
        var unit: String?
    }

    var ingredients: [GeneratedIngredient]
    var steps: [String]
}
