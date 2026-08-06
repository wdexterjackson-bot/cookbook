//
//  CookbookDeletionCoordinator.swift
//  cookbook
//
//  Deleting a Cookbook cascade-deletes its recipes (and their photos)
//  rather than re-parenting them onto another cookbook — a user who
//  deletes a cookbook they don't want anymore shouldn't end up with its
//  recipes left behind as orphaned, invisible data.
//

import Foundation
import SwiftData

enum CookbookDeletionCoordinator {
    static func recipeCount(for cookbook: Cookbook, in context: ModelContext) -> Int {
        let cookbookID = cookbook.id
        let descriptor = FetchDescriptor<Recipe>(predicate: #Predicate<Recipe> { $0.cookbookID == cookbookID })
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    static func deleteCookbookAndItsRecipes(_ cookbook: Cookbook, in context: ModelContext) {
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
