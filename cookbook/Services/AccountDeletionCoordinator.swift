//
//  AccountDeletionCoordinator.swift
//  cookbook
//
//  The reverse of PostSignInCoordinator: instead of claiming guest data
//  onto a new account, this clears everything tied to an account that's
//  about to be deleted, so a fresh signup afterward is a genuinely blank
//  slate. Does NOT call AuthServicing.deleteAccount() itself — callers run
//  this first (it can be safely retried; the Firebase Auth deletion,
//  irreversible and identity-destroying, happens only after it succeeds).
//

import Foundation
import SwiftData

enum AccountDeletionError: Error, Equatable {
    /// Deleting would strand one or more Family Cookbooks with no admin —
    /// same invariant GroupsServicing.leaveGroup already enforces (GRP-008),
    /// checked up front here so deletion can be blocked cleanly before
    /// anything is actually removed, rather than failing partway through.
    case blockedByAdminOnlyCookbooks(cookbookNames: [String])
}

enum AccountDeletionCoordinator {
    static func deleteAllData(
        for userID: String,
        modelContext: ModelContext,
        groupsService: GroupsServicing,
        entitlementService: EntitlementServicing
    ) async throws {
        let memberships = try await groupsService.fetchMemberships(forUser: userID).filter { $0.status == .active }

        var blockingCookbookNames: [String] = []
        for membership in memberships {
            let groupMemberships = try await groupsService.fetchMemberships(forGroup: membership.groupID)
            // Being the last admin only blocks deletion if it would strand
            // a still-populated group. If they're also the last active
            // member overall, leaveGroup below deletes the group entirely
            // instead of stranding it, so that case doesn't need blocking.
            guard GroupPolicy.isLastActiveAdmin(userID, in: groupMemberships),
                  !GroupPolicy.isLastActiveMember(userID, in: groupMemberships) else { continue }
            if let group = try await groupsService.fetchGroup(id: membership.groupID) {
                blockingCookbookNames.append(group.cookbookName)
            }
        }
        guard blockingCookbookNames.isEmpty else {
            throw AccountDeletionError.blockedByAdminOnlyCookbooks(cookbookNames: blockingCookbookNames)
        }

        for membership in memberships {
            // Pre-flight already ruled out stranding any group; a failure
            // here is a secondary concern, not worth blocking the deletion
            // the user actually asked for. When this user is a group's last
            // active member, leaveGroup deletes the whole group rather than
            // just marking this membership left.
            try? await groupsService.leaveGroup(groupID: membership.groupID, userID: userID)
        }

        deleteLocalData(ownerID: userID, in: modelContext)

        try? await entitlementService.deleteEntitlement(userID: userID)
    }

    private static func deleteLocalData(ownerID: String, in context: ModelContext) {
        let recipeDescriptor = FetchDescriptor<Recipe>(predicate: #Predicate { $0.ownerID == ownerID })
        let recipes = (try? context.fetch(recipeDescriptor)) ?? []
        for recipe in recipes {
            if let heroPhotoFilename = recipe.heroPhotoFilename {
                PhotoStore.delete(heroPhotoFilename)
            }
            for filename in recipe.galleryPhotoFilenames {
                PhotoStore.delete(filename)
            }
            context.delete(recipe)
        }

        let cookbookDescriptor = FetchDescriptor<Cookbook>(predicate: #Predicate { $0.ownerID == ownerID })
        let cookbooks = (try? context.fetch(cookbookDescriptor)) ?? []
        for cookbook in cookbooks {
            context.delete(cookbook)
        }

        try? context.save()
    }
}
