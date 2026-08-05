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

    static var id: String {
        if let existing = UserDefaults.standard.string(forKey: defaultsKey) {
            return existing
        }
        let newID = UUID().uuidString
        UserDefaults.standard.set(newID, forKey: defaultsKey)
        return newID
    }
}
