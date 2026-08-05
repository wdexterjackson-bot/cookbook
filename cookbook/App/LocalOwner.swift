//
//  LocalOwner.swift
//  cookbook
//
//  A stable per-device identifier used as Recipe.ownerID until real
//  accounts exist (Phase 2). Generated once, persisted in UserDefaults.
//

import Foundation

enum LocalOwner {
    private static let defaultsKey = "com.vibeapp.cookbook.localOwnerID"

    /// A `static let`, not a computed `var`: Swift guarantees a global/static
    /// stored property's initializer runs exactly once even under concurrent
    /// access. A computed-every-access version raced under Swift Testing's
    /// parallel test execution — two concurrent first-accesses could each
    /// generate and return a *different* UUID before either write landed.
    static let id: String = {
        if let existing = UserDefaults.standard.string(forKey: defaultsKey) {
            return existing
        }
        let newID = UUID().uuidString
        UserDefaults.standard.set(newID, forKey: defaultsKey)
        return newID
    }()
}
