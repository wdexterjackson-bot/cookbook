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
    /// A bundled, pre-made design (CookbookCoverStyleCatalog) the user
    /// picked instead of a plain color — nil means none chosen. Optional
    /// with an inline nil default, same reasoning as chaptersManuallyReordered's
    /// comment below: SwiftData migration needs the literal default on
    /// the property itself.
    var coverStyleImageName: String? = nil
    var coverImageFilename: String?

    /// Ordering across a user's multiple cookbooks.
    var sortOrder: Int

    var createdAt: Date
    var updatedAt: Date

    /// True once the user has been through CookbookConfigurationView at
    /// least once for this cookbook — distinguishes "created via Restore
    /// from Cloud/Backup, never actually seen by the user" from
    /// "deliberately left at defaults," which is what the first-run
    /// welcome-sheet trigger (4E) checks.
    var hasBeenConfigured: Bool

    /// False until the user actually drags to reorder chapters in
    /// CookbookConfigurationView. While false, RecipeListView sorts
    /// chapters by recipe count (highest first) instead of
    /// CookbookSection.sortOrder — once true, sortOrder is respected
    /// exactly as the user arranged it, permanently.
    ///
    /// The inline `= false` here (not just in init()) is load-bearing:
    /// SwiftData's automatic lightweight migration needs a literal
    /// default on the property declaration itself to backfill this
    /// value on every Cookbook row that existed before this field did —
    /// without it, opening an existing on-disk store throws ("missing
    /// attribute values on mandatory destination attribute") instead of
    /// migrating, confirmed by actually hitting that crash against this
    /// project's own real, already-populated Simulator store.
    var chaptersManuallyReordered: Bool = false

    /// Backing storage for `storageMode` below — a plain Bool, not the
    /// StorageMode enum directly. SwiftData's automatic lightweight
    /// migration reliably backfills new *primitive* (Bool/Int/String)
    /// properties given an inline literal default (chaptersManuallyReordered
    /// above is the proven example), but a custom Codable-enum-typed
    /// stored property is a real, documented SwiftData rough edge — adding
    /// `var storageMode: StorageMode = .local` directly here crashed every
    /// save on this app's existing on-disk store (`swift_dynamicCastFailure`
    /// deep inside SwiftData, observed 2026-08-08 from a totally unrelated
    /// CookbookConfigurationView.save() call). A Bool sidesteps the issue
    /// entirely while `storageMode` below keeps the same enum-typed API
    /// for every other file in this feature.
    var isCloudSynced: Bool = false

    /// Last time this cookbook was successfully pushed to or pulled from
    /// the cloud — nil means never synced. Informational only (UI cache,
    /// not security/ordering-sensitive), so a client-set `Date()` is fine
    /// rather than round-tripping a server timestamp.
    var lastSyncedAt: Date? = nil

    /// On-device-only (default) vs. pushed to Firestore/Storage via
    /// Personal Cookbook Cloud Sync — see StorageMode.swift and
    /// `isCloudSynced`'s comment for why this is computed, not stored
    /// directly. Deliberately excluded from CookbookBackupService's local
    /// file backup/restore payload — a restored cookbook always lands as
    /// `.local` regardless of the source's mode, since restoring onto a
    /// new device shouldn't silently start pushing data to the cloud
    /// before the user re-confirms that's what they want.
    var storageMode: StorageMode {
        get { isCloudSynced ? .cloudSynced : .local }
        set { isCloudSynced = (newValue == .cloudSynced) }
    }

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
        self.coverStyleImageName = nil
        self.coverImageFilename = nil
        self.sortOrder = sortOrder
        self.createdAt = .now
        self.updatedAt = .now
        self.hasBeenConfigured = false
        self.chaptersManuallyReordered = false
        self.isCloudSynced = false
        self.lastSyncedAt = nil
        self.sections = []
    }
}
