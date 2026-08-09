//
//  InMemoryPersonalCookbookSyncService.swift
//  cookbook
//

import Foundation

final class InMemoryPersonalCookbookSyncService: PersonalCookbookSyncServicing {
    private(set) var cookbooksByID: [UUID: PersonalCookbookDoc] = [:]
    private(set) var recipesByCookbookID: [UUID: [PersonalCookbookRecipeDoc]] = [:]
    var stubbedError: Error?

    func push(_ cookbook: PersonalCookbookDoc, recipes: [PersonalCookbookRecipeDoc]) async throws {
        if let stubbedError { throw stubbedError }
        cookbooksByID[cookbook.id] = cookbook
        recipesByCookbookID[cookbook.id] = recipes
    }

    func fetchSyncedCookbooks(forUser userID: String) async throws -> [PersonalCookbookSummary] {
        if let stubbedError { throw stubbedError }
        return cookbooksByID.values
            .filter { $0.ownerUserID == userID }
            .map { PersonalCookbookSummary(id: $0.id, title: $0.title, updatedAt: $0.updatedAt) }
    }

    func pull(cookbookID: UUID, ownerUserID: String) async throws -> (cookbook: PersonalCookbookDoc, recipes: [PersonalCookbookRecipeDoc]) {
        if let stubbedError { throw stubbedError }
        guard let cookbook = cookbooksByID[cookbookID] else {
            throw PersonalCookbookSyncError.notFound
        }
        return (cookbook, recipesByCookbookID[cookbookID] ?? [])
    }
}
