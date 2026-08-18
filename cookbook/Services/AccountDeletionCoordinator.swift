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
        entitlementService: EntitlementServicing,
        userProfileService: UserProfileServicing,
        publicationsService: PublicationsServicing = InMemoryPublicationsService(),
        friendsService: FriendsServicing = FirestoreFriendsService(),
        personalCookbookSyncService: PersonalCookbookSyncServicing = FirestorePersonalCookbookSyncService(),
        personalCookbookPhotoUploadService: PersonalCookbookPhotoUploadServicing = FirebasePersonalCookbookPhotoUploadService()
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
            // A group can now hold several cookbooks — being the last
            // admin strands all of them, so every one gets listed, not
            // just a single "the" cookbook.
            let cookbooks = try await groupsService.fetchGroupCookbooks(forGroup: membership.groupID)
            blockingCookbookNames.append(contentsOf: cookbooks.map(\.cookbookName))
        }
        guard blockingCookbookNames.isEmpty else {
            throw AccountDeletionError.blockedByAdminOnlyCookbooks(cookbookNames: blockingCookbookNames)
        }

        // Tombstone attribution on every publication this user owns, and
        // every comment they left (even on publications they don't own),
        // in every group they're still an active member of, *before*
        // leaving any of them below — firestore.rules' publication/comment
        // read/update rules all require active membership, so this window
        // closes the moment leaveGroup runs. Best-effort (a failure here
        // shouldn't block the deletion the user actually asked for, same
        // reasoning as the entitlement/profile cleanup below), but PRD
        // §6.6 wants descendants and remaining group members to see
        // "Original contributor deleted"/"Deleted User" rather than a
        // publication or comment that silently still shows a
        // since-deleted account's name forever. Likes are deliberately
        // left untouched — they carry no attribution to show, and still
        // counting toward a publication's likeCount is the intended
        // retention behavior, not an oversight.
        for membership in memberships {
            let groupPublications = (try? await publicationsService.fetchAllPublications(forGroup: membership.groupID)) ?? []
            for publication in groupPublications {
                if publication.ownerUserID == userID {
                    try? await publicationsService.tombstoneOwnerAttribution(publication.id, actingUserID: userID)
                }
                let comments = (try? await publicationsService.fetchComments(publication.id)) ?? []
                for comment in comments where comment.authorUserID == userID {
                    try? await publicationsService.tombstoneCommentAuthorship(comment.id, publicationID: publication.id, actingUserID: userID)
                }
            }
        }

        for membership in memberships {
            // Pre-flight already ruled out stranding any group; a failure
            // here is a secondary concern, not worth blocking the deletion
            // the user actually asked for. When this user is a group's last
            // active member, leaveGroup deletes the whole group rather than
            // just marking this membership left.
            try? await groupsService.leaveGroup(groupID: membership.groupID, userID: userID)
        }

        // Best-effort, before deleteLocalData below clears the SwiftData
        // records this needs (cookbook.id/storageMode) — a cloud-synced
        // cookbook's Firestore doc and every photo it uploaded to Storage
        // would otherwise sit there forever, orphaned, after the account
        // that owned them is gone. Same non-fatal precedent as the
        // entitlement/profile cleanup below: a network hiccup here
        // shouldn't block the deletion the user actually asked for.
        let cloudSyncedCookbooks = (try? modelContext.fetch(
            FetchDescriptor<Cookbook>(predicate: #Predicate<Cookbook> { $0.ownerID == userID })
        ))?.filter { $0.storageMode == .cloudSynced } ?? []
        for cookbook in cloudSyncedCookbooks {
            await PersonalCookbookSyncCoordinator.deleteFromCloud(
                cookbookID: cookbook.id, ownerUserID: userID,
                syncService: personalCookbookSyncService, photoUploadService: personalCookbookPhotoUploadService
            )
        }

        // Best-effort, same non-fatal precedent as everything else here:
        // otherwise a deleted user leaves permanent ghosts behind — a
        // friendship the other party can never detect is dead, or a
        // pending request that sits forever, un-resolvable, in someone's
        // Messages/Home. Declining rather than silently deleting the
        // incoming requests so respondToFriendRequest's normal state
        // transition (and the recipient-side notification it implies)
        // still runs.
        let outgoingFriendRequests = (try? await friendsService.fetchFriendRequests(bySender: userID)) ?? []
        for request in outgoingFriendRequests {
            try? await friendsService.cancelFriendRequest(request.id, actingUserID: userID)
        }
        let incomingFriendRequests = (try? await friendsService.fetchFriendRequests(forRecipient: userID)) ?? []
        for request in incomingFriendRequests {
            try? await friendsService.respondToFriendRequest(request.id, accept: false, respondingUserID: userID)
        }
        let friendships = (try? await friendsService.fetchFriends(forUser: userID)) ?? []
        for friendship in friendships {
            try? await friendsService.removeFriend(friendship.id, actingUserID: userID)
        }

        try deleteLocalData(ownerID: userID, in: modelContext)

        try? await entitlementService.deleteEntitlement(userID: userID)
        try? await userProfileService.deleteProfile(userID: userID)
    }

    /// Unlike the entitlement/profile cleanup below, a failure here isn't
    /// best-effort — this is the user's own local data, and a save failure
    /// would leave photos deleted from disk while their SwiftData records
    /// still exist (or vice versa), silently. Throws so the caller can
    /// surface a real error instead of reporting deletion as successful
    /// when it wasn't.
    private static func deleteLocalData(ownerID: String, in context: ModelContext) throws {
        let recipeDescriptor = FetchDescriptor<Recipe>(predicate: #Predicate { $0.ownerID == ownerID })
        let recipes = try context.fetch(recipeDescriptor)
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
        let cookbooks = try context.fetch(cookbookDescriptor)
        for cookbook in cookbooks {
            context.delete(cookbook)
        }

        try context.save()
    }
}
