//
//  ActiveCookbookState.swift
//  cookbook
//
//  Which of the owner's (possibly several) Cookbooks is currently being
//  viewed. Persists the last-active id like LocalOwner does, so relaunching
//  the app returns to wherever the user left off.
//

import Foundation
import Observation

@MainActor
@Observable
final class ActiveCookbookState {
    private static let defaultsKey = "com.vibeapp.cookbook.activeCookbookID"

    private(set) var activeCookbookID: UUID?

    init() {
        if let stored = UserDefaults.standard.string(forKey: Self.defaultsKey) {
            activeCookbookID = UUID(uuidString: stored)
        }
    }

    func setActive(_ cookbookID: UUID) {
        activeCookbookID = cookbookID
        UserDefaults.standard.set(cookbookID.uuidString, forKey: Self.defaultsKey)
    }
}
