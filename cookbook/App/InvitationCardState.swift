//
//  InvitationCardState.swift
//  cookbook
//
//  Local, per-owner UI state for the Home dashboard's Messages
//  invitation cards — deliberately separate from the real Invitation
//  record's own accept/decline outcome (GroupsServicing.respondToInvitation).
//  Tapping "Decline" only enters this soft state (Join/Decline disabled,
//  Reconsider/Delete shown); the real backend decline is deferred until
//  "Delete" is actually tapped, so "Reconsider" never needs to undo a
//  server-side response that already happened — there's nothing to undo,
//  since nothing was sent yet. This also covers the MFB placeholder
//  invitation, which has no real Invitation record to decline at all.
//
//  Same lightweight UserDefaults-backed shape as DismissedCloudCookbookPrompts,
//  owner-scoped (unlike that one) so one account's card state never leaks
//  into another signed-in account's dashboard on a shared device.
//

import Foundation

enum InvitationCardState {
    private static func softDeclinedKey(ownerID: String) -> String {
        "com.vibeapp.cookbook.softDeclinedInvitationIDs.\(ownerID)"
    }
    private static func deletedKey(ownerID: String) -> String {
        "com.vibeapp.cookbook.deletedInvitationIDs.\(ownerID)"
    }

    static func softDeclinedIDs(ownerID: String, defaults: UserDefaults = .standard) -> Set<String> {
        Set(defaults.stringArray(forKey: softDeclinedKey(ownerID: ownerID)) ?? [])
    }

    static func deletedIDs(ownerID: String, defaults: UserDefaults = .standard) -> Set<String> {
        Set(defaults.stringArray(forKey: deletedKey(ownerID: ownerID)) ?? [])
    }

    static func setSoftDeclined(_ id: String, ownerID: String, defaults: UserDefaults = .standard) {
        var ids = softDeclinedIDs(ownerID: ownerID, defaults: defaults)
        ids.insert(id)
        defaults.set(Array(ids), forKey: softDeclinedKey(ownerID: ownerID))
    }

    static func clearSoftDeclined(_ id: String, ownerID: String, defaults: UserDefaults = .standard) {
        var ids = softDeclinedIDs(ownerID: ownerID, defaults: defaults)
        ids.remove(id)
        defaults.set(Array(ids), forKey: softDeclinedKey(ownerID: ownerID))
    }

    static func setDeleted(_ id: String, ownerID: String, defaults: UserDefaults = .standard) {
        var deleted = deletedIDs(ownerID: ownerID, defaults: defaults)
        deleted.insert(id)
        defaults.set(Array(deleted), forKey: deletedKey(ownerID: ownerID))
        clearSoftDeclined(id, ownerID: ownerID, defaults: defaults)
    }
}
