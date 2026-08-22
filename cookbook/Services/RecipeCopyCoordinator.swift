//
//  RecipeCopyCoordinator.swift
//  cookbook
//
//  Copy to Personal (PRD §6) — the one place a group-published recipe
//  becomes a new, independently-editable local Recipe owned by the
//  copier. Mirrors RecipePublishingCoordinator's shape/scope: one
//  free function, no shared state, SwiftData write only (never touches
//  Firestore — the source Publication is left completely untouched).
//
//  Lineage on the new Recipe: immediateSourceRecipeID always points at
//  the Publication's own sourceRecipeID (the recipe it was published
//  from); rootOriginRecipeID comes straight from the Publication content's
//  own rootOriginRecipeID snapshot (populated at publish time by
//  PublicationContentSnapshot.make — already correctly the true root even
//  across multiple copy/republish hops, not recomputed here). Owner is the
//  copier, always — never the source's owner, matching "copy creates
//  ownership" (PRD §6.1).
//

import Foundation
import SwiftData

enum RecipeCopyCoordinator {
    /// Saves immediately (unlike RecipePublishingCoordinator, which never
    /// touches SwiftData) — same save-or-rollback shape as
    /// RecipeFileImportCoordinator.commit, so a mid-batch SwiftData error
    /// never leaves a half-inserted Recipe for some later, unrelated save()
    /// elsewhere in the app to silently flush.
    static func copy(
        _ publication: Publication,
        forUserID copierUserID: String,
        into cookbook: Cookbook,
        modelContext: ModelContext
    ) -> Result<Recipe, Error> {
        let content = publication.content
        let recipe = Recipe(
            ownerID: copierUserID,
            title: content.title,
            summary: content.summary,
            yield: content.yield,
            sourceType: .manual
        )
        recipe.cookbookID = cookbook.id
        recipe.notes = content.notes
        recipe.tags = content.tags
        recipe.totalTimeMinutes = content.totalTimeMinutes

        recipe.ingredientSections = content.ingredientSections.enumerated().map { sectionIndex, section in
            let ingredientSection = IngredientSection(heading: section.heading, sortOrder: sectionIndex)
            ingredientSection.ingredients = section.ingredients.enumerated().map { index, ingredient in
                Ingredient(displayText: ingredient.displayText, name: ingredient.displayText, isOptional: ingredient.isOptional, sortOrder: index)
            }
            return ingredientSection
        }
        recipe.stepSections = content.stepSections.enumerated().map { sectionIndex, section in
            let stepSection = StepSection(heading: section.heading, sortOrder: sectionIndex)
            stepSection.steps = section.steps.enumerated().map { index, text in
                Step(text: text, sortOrder: index)
            }
            return stepSection
        }

        // Attribution (who to credit) is separate from lineage (the copy
        // chain) — see Recipe.authorLineage's own doc comment. The copy is
        // always externally credited to whoever it was copied from; the
        // copier is never silently credited as the author.
        recipe.authorLineage = content.authorLineage
        recipe.authorLineageIsExternal = true
        recipe.videoURLs = content.videoURLs ?? []

        // Lineage — never inherited from the copier's own prior recipes,
        // always freshly stamped from this specific publication.
        recipe.immediateSourceRecipeID = UUID(uuidString: publication.sourceRecipeID)
        recipe.rootOriginRecipeID = content.rootOriginRecipeID.flatMap(UUID.init(uuidString:))
            ?? UUID(uuidString: publication.sourceRecipeID)
        recipe.sourceOwnerSnapshot = content.sourceOwnerSnapshot
        recipe.sourceGroupSnapshot = content.sourceGroupSnapshot

        modelContext.insert(recipe)
        do {
            try modelContext.save()
            return .success(recipe)
        } catch {
            modelContext.rollback()
            return .failure(error)
        }
    }

    /// Friend-to-friend recipe sharing's counterpart to the Publication
    /// overload above — same mapping, same save-or-rollback shape, just
    /// reading from a SharedRecipe instead. Kept as a separate overload
    /// rather than generalized over both types: the two source types
    /// (Publication, SharedRecipe) share a content shape but not an
    /// identity shape (groupID/cookbookID vs. none), so a shared
    /// abstraction would need to fake fields that don't apply to a plain
    /// friend share.
    static func copy(
        _ sharedRecipe: SharedRecipe,
        forUserID copierUserID: String,
        into cookbook: Cookbook,
        modelContext: ModelContext
    ) -> Result<Recipe, Error> {
        let content = sharedRecipe.content
        let recipe = Recipe(
            ownerID: copierUserID,
            title: content.title,
            summary: content.summary,
            yield: content.yield,
            sourceType: .manual
        )
        recipe.cookbookID = cookbook.id
        recipe.notes = content.notes
        recipe.tags = content.tags
        recipe.totalTimeMinutes = content.totalTimeMinutes

        recipe.ingredientSections = content.ingredientSections.enumerated().map { sectionIndex, section in
            let ingredientSection = IngredientSection(heading: section.heading, sortOrder: sectionIndex)
            ingredientSection.ingredients = section.ingredients.enumerated().map { index, ingredient in
                Ingredient(displayText: ingredient.displayText, name: ingredient.displayText, isOptional: ingredient.isOptional, sortOrder: index)
            }
            return ingredientSection
        }
        recipe.stepSections = content.stepSections.enumerated().map { sectionIndex, section in
            let stepSection = StepSection(heading: section.heading, sortOrder: sectionIndex)
            stepSection.steps = section.steps.enumerated().map { index, text in
                Step(text: text, sortOrder: index)
            }
            return stepSection
        }

        recipe.authorLineage = content.authorLineage
        recipe.authorLineageIsExternal = true
        recipe.videoURLs = content.videoURLs ?? []

        recipe.immediateSourceRecipeID = UUID(uuidString: sharedRecipe.sourceRecipeID)
        recipe.rootOriginRecipeID = content.rootOriginRecipeID.flatMap(UUID.init(uuidString:))
            ?? UUID(uuidString: sharedRecipe.sourceRecipeID)
        recipe.sourceOwnerSnapshot = content.sourceOwnerSnapshot
        // No group involved in a friend-to-friend share — a plain fixed
        // label rather than nil, so RecipeDetailView's existing
        // sharedFromText still shows *something* rather than silently
        // dropping this recipe's lineage.
        recipe.sourceGroupSnapshot = "a friend"

        modelContext.insert(recipe)
        do {
            try modelContext.save()
            return .success(recipe)
        } catch {
            modelContext.rollback()
            return .failure(error)
        }
    }
}
