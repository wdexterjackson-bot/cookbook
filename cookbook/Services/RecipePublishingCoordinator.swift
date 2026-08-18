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
    /// Returns `true` whenever there was nothing to upload in the first
    /// place — only `false` distinguishes a genuine upload failure, so
    /// callers can tell the difference and let the user know the text
    /// published but the photo didn't, instead of the failure being
    /// invisible (as it was before this returned anything).
    @discardableResult
    static func publish(
        _ recipe: Recipe,
        to group: FamilyGroup,
        cookbook: GroupCookbook,
        ownerUserID: String,
        commentsEnabled: Bool = false,
        publicationsService: PublicationsServicing,
        photoUploadService: RecipePhotoUploadServicing
    ) async throws -> Bool {
        var coverImageURL: String?
        var photoUploadSucceeded = true
        if let filename = recipe.heroPhotoFilename, let imageData = PhotoStore.data(for: filename) {
            // Best-effort: a photo upload hiccup shouldn't block publishing
            // the recipe's text content — but it's still worth reporting
            // back to the caller rather than silently pretending it worked.
            do {
                coverImageURL = try await photoUploadService.upload(
                    imageData: imageData,
                    groupID: group.id,
                    cookbookID: cookbook.id,
                    ownerUserID: ownerUserID,
                    sourceRecipeID: recipe.id.uuidString
                ).absoluteString
            } catch {
                photoUploadSucceeded = false
            }
        }

        let content = PublicationContentSnapshot.make(from: recipe, coverImageURL: coverImageURL)
        let publication = try await publicationsService.publish(content, sourceRecipeID: recipe.id.uuidString, to: group.id, cookbookID: cookbook.id, ownerUserID: ownerUserID)
        // Best-effort, same non-fatal precedent as the photo upload above
        // — a failure here shouldn't undo an otherwise-successful publish.
        try? await publicationsService.setCommentsEnabled(publication.id, enabled: commentsEnabled, actingUserID: ownerUserID)
        return photoUploadSucceeded
    }
}
