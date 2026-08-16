//
//  CookbookDeletionCoordinator.swift
//  cookbook
//
//  Deleting a Cookbook cascade-deletes its recipes (and their photos)
//  rather than re-parenting them onto another cookbook — a user who
//  deletes a cookbook they don't want anymore shouldn't end up with its
//  recipes left behind as orphaned, invisible data. For a cloud-synced
//  cookbook, that now includes its cloud footprint too (Firestore doc +
//  every uploaded photo) via PersonalCookbookSyncCoordinator.deleteFromCloud
//  — previously only the local copy was ever cleaned up, leaving the
//  cloud copy (and its Storage cost) behind forever.
//

import Foundation
import SwiftData

enum CookbookDeletionCoordinator {
    static func recipeCount(for cookbook: Cookbook, in context: ModelContext) -> Int {
        let cookbookID = cookbook.id
        let descriptor = FetchDescriptor<Recipe>(predicate: #Predicate<Recipe> { $0.cookbookID == cookbookID })
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    static func deleteCookbookAndItsRecipes(
        _ cookbook: Cookbook,
        ownerUserID: String,
        in context: ModelContext,
        syncService: PersonalCookbookSyncServicing = FirestorePersonalCookbookSyncService(),
        photoUploadService: PersonalCookbookPhotoUploadServicing = FirebasePersonalCookbookPhotoUploadService()
    ) async {
        if cookbook.storageMode == .cloudSynced {
            await PersonalCookbookSyncCoordinator.deleteFromCloud(
                cookbookID: cookbook.id, ownerUserID: ownerUserID,
                syncService: syncService, photoUploadService: photoUploadService
            )
        }

        let cookbookID = cookbook.id
        let descriptor = FetchDescriptor<Recipe>(predicate: #Predicate<Recipe> { $0.cookbookID == cookbookID })
        let recipes = (try? context.fetch(descriptor)) ?? []
        for recipe in recipes {
            if let heroPhotoFilename = recipe.heroPhotoFilename {
                PhotoStore.delete(heroPhotoFilename)
            }
            for filename in recipe.galleryPhotoFilenames {
                PhotoStore.delete(filename)
            }
            context.delete(recipe)
        }

        context.delete(cookbook)
        try? context.save()
    }
}
