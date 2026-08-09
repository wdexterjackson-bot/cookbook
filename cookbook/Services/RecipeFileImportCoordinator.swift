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
//  Deliberately two stages, not one: `parseRecipes` only ever reads —
//  nothing touches modelContext — so the caller can show the user a
//  review screen and let them approve or discard the whole batch before
//  anything is written. `commit` is the only function that persists, and
//  only runs once the user has approved.
//

import Foundation
import SwiftData

struct DraftRecipe: Identifiable {
    let id = UUID()
    var title: String
    var chapterName: String?
    var notes: String
    var authorLineage: String?
    var ingredients: [ParsedIngredientLine]
    var steps: [String]
}

struct RecipeFileImportPreview {
    var drafts: [DraftRecipe] = []
    /// A short snippet (first line) of whatever chunk failed to parse, so
    /// the review screen can tell the user what to fix and re-import,
    /// rather than the whole batch aborting on one bad block.
    var failedChunks: [String] = []
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

    /// Stage 1 — parse only. Read-only: no Cookbook, no ModelContext,
    /// nothing persisted. `defaultAuthorLineage` is resolved once for the
    /// whole file by the caller (before parsing starts); a chunk's own
    /// "By:" line still overrides it per-recipe.
    static func parseRecipes(
        from text: String,
        defaultAuthorLineage: String?,
        lineImportService: RecipeLineImportServicing,
        onChunkProgress: @escaping @Sendable @MainActor (Int, Int) -> Void = { _, _ in }
    ) async -> RecipeFileImportPreview {
        var preview = RecipeFileImportPreview()
        let chunks = splitIntoRecipeChunks(text)
        let total = chunks.count
        // Reported before the loop starts, not just after each chunk
        // finishes — the total is known immediately, but each chunk's
        // on-device AI parse can take several seconds, so waiting for the
        // first callback left the UI showing an indeterminate spinner
        // with no total for that whole first chunk (the entire parse, for
        // a single-recipe file).
        await onChunkProgress(0, total)

        for (index, chunk) in chunks.enumerated() {
            do {
                let parsed = try await lineImportService.parseLines(from: chunk)
                if let title = parsed.title, !title.isEmpty {
                    preview.drafts.append(DraftRecipe(
                        title: title,
                        chapterName: parsed.chapterName,
                        notes: parsed.notes ?? "",
                        authorLineage: parsed.authorLineageText ?? defaultAuthorLineage,
                        ingredients: parsed.ingredients,
                        steps: parsed.steps
                    ))
                } else {
                    preview.failedChunks.append(String(chunk.prefix(60)))
                }
            } catch {
                preview.failedChunks.append(String(chunk.prefix(60)))
            }
            await onChunkProgress(index + 1, total)
        }

        return preview
    }

    /// Stage 2 — only called once the user has reviewed and approved the
    /// preview. Creates real Recipe (and, where needed, CookbookSection)
    /// SwiftData objects and saves once. A chapter name with no
    /// case-insensitive match on the target cookbook is created rather
    /// than left unfiled — recipes sharing a new chapter name within the
    /// same batch reuse the one section instead of creating duplicates.
    static func commit(
        _ drafts: [DraftRecipe],
        into cookbook: Cookbook,
        ownerID: String,
        modelContext: ModelContext
    ) -> Result<Int, Error> {
        for draft in drafts {
            let recipe = Recipe(ownerID: ownerID, title: draft.title, sourceType: .manual)
            recipe.cookbookID = cookbook.id
            recipe.sectionID = resolveChapter(named: draft.chapterName, in: cookbook)?.id
            recipe.notes = draft.notes
            recipe.authorLineage = draft.authorLineage
            recipe.ingredientSections = buildIngredientSection(from: draft.ingredients).map { [$0] } ?? []
            recipe.stepSections = buildStepSection(from: draft.steps).map { [$0] } ?? []
            modelContext.insert(recipe)
        }

        do {
            try modelContext.save()
            return .success(drafts.count)
        } catch {
            return .failure(error)
        }
    }

    /// Case-insensitive match against the target cookbook's existing
    /// chapters; creates a new one (appended to `cookbook.sections`, same
    /// pattern CookbookConfigurationView uses) when nothing matches.
    private static func resolveChapter(named chapterName: String?, in cookbook: Cookbook) -> CookbookSection? {
        guard let chapterName else { return nil }
        let trimmed = chapterName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let existing = cookbook.sections.first(where: { $0.title.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return existing
        }
        let newSection = CookbookSection(title: trimmed, sortOrder: cookbook.sections.count)
        cookbook.sections.append(newSection)
        return newSection
    }

    private static func buildIngredientSection(from parsedIngredients: [ParsedIngredientLine]) -> IngredientSection? {
        guard !parsedIngredients.isEmpty else { return nil }
        let section = IngredientSection(heading: nil, sortOrder: 0)
        section.ingredients = parsedIngredients.enumerated().map { index, parsed in
            Ingredient(
                displayText: displayText(for: parsed),
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

    /// Also used by the review screen so the preview shows ingredients
    /// formatted exactly as they'll be saved.
    static func displayText(for ingredient: ParsedIngredientLine) -> String {
        var parts: [String] = []
        if let quantity = ingredient.quantity {
            parts.append(quantity.formatted(.number.precision(.fractionLength(0...2))))
        }
        if let unit = ingredient.unit, !unit.isEmpty {
            parts.append(unit)
        }
        if !ingredient.name.isEmpty {
            parts.append(ingredient.name)
        }
        return parts.isEmpty ? ingredient.name : parts.joined(separator: " ")
    }
}
