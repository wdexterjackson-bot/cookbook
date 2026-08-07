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
        let trimmed = Self.strippingBareSectionLabels(text).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw RecipeLineImportError.emptyInput
        }
        guard isAvailable else {
            throw RecipeLineImportError.unavailable
        }

        let session = LanguageModelSession {
            """
            You extract structured recipe data from pasted, possibly messy
            text. The text may use explicit labels ("Name:", "Section:",
            "By:", "Notes:") — treat those as authoritative when present.
            Extract:

            - title: the dish's name. Look for a "Name:" label first, or an
              unambiguous title-like first line. Leave blank if not clearly
              identifiable — never guess.
            - chapterName: which cookbook chapter/category this recipe
              belongs to (e.g. "Desserts", "Appetizers"), from a "Section:"
              label. Leave blank if there's no such label — never infer this
              from the recipe's content.
            - authorLineageText: who this recipe is credited to, from a
              "By:" label — copy the text after it verbatim, whether it's
              just a name ("By: Jane Doe") or a name with a location ("By:
              Jane Doe of Baltimore, MD"). Leave blank if there's no such
              label — never infer authorship from the recipe's content.
            - ingredients and steps: classify each remaining line as either
              an ingredient or an instruction step, preserving original
              order within each list. For ingredients, separate the
              quantity (a plain number — convert fractions like "1/2" to
              0.5) and unit (e.g. cup, tbsp, oz, g) from the ingredient name
              whenever possible; omit quantity or unit for a line that
              doesn't clearly have one (e.g. "salt to taste").
            - notes: trailing commentary that isn't itself a cooking
              instruction — serving size, substitution tips, storage
              advice, etc. Look for a "Notes:" label first; otherwise, if
              text after the last real instruction step reads as commentary
              rather than another step, treat it as notes instead of
              appending it to steps. Leave blank if there's nothing like
              that.
            """
        }

        do {
            let response = try await session.respond(to: trimmed, generating: GeneratedRecipeLines.self)
            let content = response.content
            let ingredients = content.ingredients.map {
                ParsedIngredientLine(name: $0.name, quantity: $0.quantity, unit: $0.unit)
            }
            return ParsedRecipeLines(
                title: Self.nonBlank(content.title),
                chapterName: Self.nonBlank(content.chapterName),
                ingredients: ingredients,
                steps: content.steps,
                notes: Self.nonBlank(content.notes),
                authorLineageText: Self.nonBlank(content.authorLineageText)
            )
        } catch {
            throw RecipeLineImportError.parsingFailed
        }
    }

    /// Some sources (e.g. recipe-box PDF exports) label their ingredient
    /// and step lists with a bare header line — "Ingredients", "Directions"
    /// — rather than the colon-suffixed labels this parser otherwise looks
    /// for. Left in, a small on-device model can misread the header itself
    /// as an ingredient or step; stripping known bare headers up front is
    /// more reliable than trusting the model to recognize and discard them.
    private static let bareSectionLabels: Set<String> = ["ingredients", "directions", "instructions", "steps"]

    private static func strippingBareSectionLabels(_ text: String) -> String {
        text.components(separatedBy: .newlines)
            .filter { !bareSectionLabels.contains($0.trimmingCharacters(in: .whitespaces).lowercased()) }
            .joined(separator: "\n")
    }

    private static func nonBlank(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
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

    var title: String?
    var chapterName: String?
    var authorLineageText: String?
    var ingredients: [GeneratedIngredient]
    var steps: [String]
    var notes: String?
}
