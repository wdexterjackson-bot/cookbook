//
//  RecipePublishingCoordinator.swift
//  cookbook
//
//  The one place that actually publishes a recipe's current local
//  content into a Family Cookbook — used by both the single-recipe
//  "Publish to a Family Cookbook" flow (PublishToFamilyCookbookView) and
//  the Administrator screen's bulk "Publish a Cookbook" action, so the
//  content-snapshot + photo-upload + publish sequence exists in exactly
//  one place. Publishing the same recipe to the same group again updates
//  the existing Publication in place (LIN-001) — never worries about
//  create-vs-update.
//

import Foundation

enum RecipePublishingCoordinator {
    static func publish(
        _ recipe: Recipe,
        to group: FamilyGroup,
        ownerUserID: String,
        publicationsService: PublicationsServicing,
        photoUploadService: RecipePhotoUploadServicing
    ) async throws {
        var coverImageURL: String?
        if let filename = recipe.heroPhotoFilename, let imageData = PhotoStore.data(for: filename) {
            // Best-effort: a photo upload hiccup shouldn't block publishing
            // the recipe's text content.
            coverImageURL = try? await photoUploadService.upload(
                imageData: imageData,
                groupID: group.id,
                ownerUserID: ownerUserID,
                sourceRecipeID: recipe.id.uuidString
            ).absoluteString
        }

        let content = PublicationContentSnapshot.make(from: recipe, coverImageURL: coverImageURL)
        _ = try await publicationsService.publish(content, sourceRecipeID: recipe.id.uuidString, to: group.id, ownerUserID: ownerUserID)
    }
}
