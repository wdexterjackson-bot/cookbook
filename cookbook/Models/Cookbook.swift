//
//  Cookbook.swift
//  cookbook
//
//  A user can own multiple Cookbooks (a genuine architecture change from
//  Phase 1's implicit single "Personal Cookbook"). Named Cookbook, not
//  Book, to stay unambiguous; CookbookSection (not Section) avoids
//  shadowing SwiftUI.Section the way a bare "Group" model once shadowed
//  SwiftUI.Group (see the reusable-app-stack/project-scope memory).
//

import Foundation
import SwiftData

@Model
final class Cookbook {
    var id: UUID
    var ownerID: String

    var title: String
    /// Hex string (no leading #) — round-trips simply, converted to a
    /// SwiftUI Color via Color(hex:) at display time.
    var coverColorHex: String
    var coverImageFilename: String?

    /// Ordering across a user's multiple cookbooks.
    var sortOrder: Int

    var createdAt: Date
    var updatedAt: Date

    /// True once the user has been through CookbookConfigurationView at
    /// least once for this cookbook — distinguishes "freshly
    /// auto-created by CookbookMigrator, never seen by the user" from
    /// "deliberately left at defaults," which is what the first-run
    /// welcome-sheet trigger (4E) checks.
    var hasBeenConfigured: Bool

    @Relationship(deleteRule: .cascade, inverse: nil)
    var sections: [CookbookSection]

    static let defaultColorHex = "C25432"

    init(
        ownerID: String,
        title: String,
        coverColorHex: String = Cookbook.defaultColorHex,
        sortOrder: Int = 0
    ) {
        self.id = UUID()
        self.ownerID = ownerID
        self.title = title
        self.coverColorHex = coverColorHex
        self.coverImageFilename = nil
        self.sortOrder = sortOrder
        self.createdAt = .now
        self.updatedAt = .now
        self.hasBeenConfigured = false
        self.sections = []
    }
}
