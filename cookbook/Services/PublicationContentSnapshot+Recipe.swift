//
//  PublicationContentSnapshot+Recipe.swift
//  cookbook
//
//  Recipe (SwiftData, local-only) -> PublicationContentSnapshot (plain
//  Codable, what actually travels to Firestore). Kept out of both model
//  files on purpose — Publication.swift stays free of a SwiftData import,
//  matching this app's existing local/cloud model separation.
//

import Foundation

extension PublicationContentSnapshot {
    /// `groupName` is nil only for callers (existing tests) that don't
    /// care about lineage — every real publish call site has a real
    /// FamilyGroup.name to pass. See Copy-to-Personal (PRD §6): a future
    /// copier's `sourceOwnerSnapshot`/`sourceGroupSnapshot` describe *this*
    /// publish action specifically (this recipe's own authorLineage, this
    /// destination group), not inherited from wherever this recipe's
    /// content originally came from — that's what `rootOriginRecipeID`
    /// alone is for, carried forward from the recipe's existing lineage if
    /// it has any (it's itself a copy being republished), or seeded from
    /// its own id if this is an original.
    static func make(from recipe: Recipe, coverImageURL: String? = nil, groupName: String? = nil) -> PublicationContentSnapshot {
        PublicationContentSnapshot(
            title: recipe.title,
            summary: recipe.summary,
            yield: recipe.yield,
            totalTimeMinutes: recipe.totalTimeMinutes,
            ingredientSections: recipe.ingredientSections
                .sorted { $0.sortOrder < $1.sortOrder }
                .map { section in
                    PublicationIngredientSection(
                        heading: section.heading,
                        ingredients: section.ingredients
                            .sorted { $0.sortOrder < $1.sortOrder }
                            .map { PublicationIngredient(displayText: $0.displayText, isOptional: $0.isOptional) }
                    )
                },
            stepSections: recipe.stepSections
                .sorted { $0.sortOrder < $1.sortOrder }
                .map { section in
                    PublicationStepSection(
                        heading: section.heading,
                        steps: section.steps
                            .sorted { $0.sortOrder < $1.sortOrder }
                            .map(\.text)
                    )
                },
            notes: recipe.notes,
            tags: recipe.tags,
            coverImageURL: coverImageURL,
            authorLineage: recipe.authorLineage,
            rootOriginRecipeID: (recipe.rootOriginRecipeID ?? recipe.id).uuidString,
            sourceOwnerSnapshot: recipe.authorLineage,
            sourceGroupSnapshot: groupName,
            videoURLs: recipe.videoURLs
        )
    }
}

extension PublicationContentSnapshot {
    /// Friend-to-friend sharing's attribution rule (ShareRecipeWithFriendView):
    /// an existing lineage always survives untouched — this only fires
    /// when there's none at all, meaning the sender's own original
    /// creation, so the recipient sees "Inspired by {sender}" rather than
    /// the misleading default "You" (which would wrongly imply *they*
    /// made it). Never applied to the Community Cookbook publish path,
    /// which has its own separate, unrelated attribution story.
    func attributingSenderIfUnattributed(_ senderDisplayName: String?) -> PublicationContentSnapshot {
        guard authorLineage?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true else { return self }
        var copy = self
        copy.authorLineage = senderDisplayName
        copy.sourceOwnerSnapshot = senderDisplayName
        return copy
    }
}
