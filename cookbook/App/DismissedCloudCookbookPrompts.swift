//
//  DismissedCloudCookbookPrompts.swift
//  cookbook
//
//  Tracks which cloud-synced cookbook ids RootTabView has already offered
//  to restore on this device, so the post-sign-in "cookbooks available"
//  prompt doesn't re-nag about the same ones every launch — while still
//  catching genuinely new ones synced from another device later. Same
//  lightweight UserDefaults-backed shape as LocalOwner/CookingSessionState.
//  `defaults` is injectable (defaults to `.standard`) rather than hard-coded,
//  matching this project's own established caution about UserDefaults.standard
//  causing real races under Swift Testing's parallel test execution.
//

import Foundation

enum DismissedCloudCookbookPrompts {
    private static let defaultsKey = "com.vibeapp.cookbook.dismissedCloudCookbookPromptIDs"

    static func hasBeenPrompted(for cookbookID: UUID, defaults: UserDefaults = .standard) -> Bool {
        dismissedIDs(defaults: defaults).contains(cookbookID.uuidString)
    }

    static func markPrompted(_ cookbookIDs: [UUID], defaults: UserDefaults = .standard) {
        guard !cookbookIDs.isEmpty else { return }
        var ids = dismissedIDs(defaults: defaults)
        for id in cookbookIDs {
            ids.insert(id.uuidString)
        }
        defaults.set(Array(ids), forKey: defaultsKey)
    }

    private static func dismissedIDs(defaults: UserDefaults) -> Set<String> {
        Set(defaults.stringArray(forKey: defaultsKey) ?? [])
    }
}
