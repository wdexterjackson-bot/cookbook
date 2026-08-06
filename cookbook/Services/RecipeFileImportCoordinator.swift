//
//  RecipeFileImportCoordinator.swift
//  cookbook
//
//  Bulk recipe import (the Administrator screen's Import action): a file
//  containing multiple recipe blocks, each one run through the same
//  on-device AI parsing already used for single-recipe paste-import
//  (RecipeLineImportServicing) — this doesn't reinvent that, it just
//  splits a file into per-recipe chunks and drives the existing call once
//  per chunk. See Recipe_Import_Format.md for the file format this expects.
//

import Foundation
import SwiftData

struct RecipeFileImportResult {
    var importedTitles: [String] = []
    /// A short snippet (first line) of whatever chunk failed to parse, so
    /// the results screen can tell the user what to fix and re-import,
    /// rather than the whole batch aborting on one bad block.
    var failedChunks: [String] = []
    /// Set if the final SwiftData save itself threw — in that case nothing
    /// in `importedTitles` actually persisted (the save is all-or-nothing),
    /// so the results screen must not report those as successes.
    var saveErrorMessage: String?
}

enum RecipeFileImportCoordinator {
    /// A new line starting with "Name:" marks the start of the next
    /// recipe — required on every recipe in a bulk file (unlike
    /// single-recipe paste-import, where a missing title is tolerated),
    /// since it's what makes splitting the file possible at all.
    static func splitIntoRecipeChunks(_ text: String) -> [String] {
        let lines = text.components(separatedBy: .newlines)
        var chunks: [[String]] = []
        for line in lines {
            if line.hasPrefix("Name:") {
                chunks.append([line])
            } else if !chunks.isEmpty {
                chunks[chunks.count - 1].append(line)
            }
            // Lines before the first "Name:" line are discarded — nothing
            // to attach them to.
        }
        return chunks
            .map { $0.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func importRecipes(
        from text: String,
        into cookbook: Cookbook,
        ownerID: String,
        defaultAuthorLineage: String?,
        lineImportService: RecipeLineImportServicing,
        modelContext: ModelContext
    ) async -> RecipeFileImportResult {
        var result = RecipeFileImportResult()

        for chunk in splitIntoRecipeChunks(text) {
            do {
                let parsed = try await lineImportService.parseLines(from: chunk)
                guard let title = parsed.title, !title.isEmpty else {
                    result.failedChunks.append(String(chunk.prefix(60)))
                    continue
                }

                let recipe = Recipe(ownerID: ownerID, title: title, sourceType: .manual)
                recipe.cookbookID = cookbook.id
                recipe.sectionID = matchingChapter(named: parsed.chapterName, in: cookbook)?.id
                recipe.notes = parsed.notes ?? ""
                recipe.authorLineage = parsed.authorLineageText ?? defaultAuthorLineage
                recipe.ingredientSections = buildIngredientSection(from: parsed.ingredients).map { [$0] } ?? []
                recipe.stepSections = buildStepSection(from: parsed.steps).map { [$0] } ?? []
                modelContext.insert(recipe)

                result.importedTitles.append(title)
            } catch {
                result.failedChunks.append(String(chunk.prefix(60)))
            }
        }

        do {
            try modelContext.save()
        } catch {
            result.saveErrorMessage = error.localizedDescription
            result.importedTitles = []
        }
        return result
    }

    /// Case-insensitive match against the target cookbook's existing
    /// chapters — never creates a new one, same "leave it unfiled rather
    /// than guess" rule as single-recipe import's chapter matching.
    private static func matchingChapter(named chapterName: String?, in cookbook: Cookbook) -> CookbookSection? {
        guard let chapterName else { return nil }
        return cookbook.sections.first { $0.title.caseInsensitiveCompare(chapterName) == .orderedSame }
    }

    private static func buildIngredientSection(from parsedIngredients: [ParsedIngredientLine]) -> IngredientSection? {
        guard !parsedIngredients.isEmpty else { return nil }
        let section = IngredientSection(heading: nil, sortOrder: 0)
        section.ingredients = parsedIngredients.enumerated().map { index, parsed in
            Ingredient(
                displayText: composeDisplayText(name: parsed.name, quantity: parsed.quantity, unit: parsed.unit),
                name: parsed.name,
                quantityValue: parsed.quantity,
                unit: parsed.unit,
                sortOrder: index
            )
        }
        return section
    }

    private static func buildStepSection(from steps: [String]) -> StepSection? {
        guard !steps.isEmpty else { return nil }
        let section = StepSection(heading: nil, sortOrder: 0)
        section.steps = steps.enumerated().map { index, text in
            Step(text: text, sortOrder: index)
        }
        return section
    }

    private static func composeDisplayText(name: String, quantity: Double?, unit: String?) -> String {
        var parts: [String] = []
        if let quantity {
            parts.append(quantity.formatted(.number.precision(.fractionLength(0...2))))
        }
        if let unit, !unit.isEmpty {
            parts.append(unit)
        }
        if !name.isEmpty {
            parts.append(name)
        }
        return parts.isEmpty ? name : parts.joined(separator: " ")
    }
}
