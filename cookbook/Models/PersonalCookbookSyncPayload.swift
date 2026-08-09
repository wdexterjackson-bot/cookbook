//
//  PersonalCookbookSyncPayload.swift
//  cookbook
//
//  Firestore-shaped mirror of Cookbook/CookbookSection/Recipe, analogous to
//  CookbookBackupArchive.swift's local-file payloads but for Personal
//  Cookbook Cloud Sync — see the plan this implements
//  (.claude/plans/mellow-spinning-flame.md) for the full design.
//
//  Two real differences from the local backup format:
//  - `id` fields are preserved, not randomized — sync needs stable ids so
//    push-then-pull round-trips to the same document and re-syncing
//    overwrites in place, unlike backup/restore's "always create fresh"
//    behavior (CookbookBackupArchive.swift's header explains why that one
//    doesn't preserve ids).
//  - `ownerUserID` is on every doc, including each recipe subdocument, so
//    firestore.rules can check ownership directly on the resource being
//    written without a cross-collection `get()` — cheaper, and this is
//    strictly single-owner data with no group-membership complexity to
//    justify the more expensive pattern.
//
//  Ingredient/step structures are reused as-is from CookbookBackupArchive
//  (IngredientSectionBackup/StepSectionBackup and friends) — they're pure
//  structural data with no base64/photo concerns, so duplicating them here
//  would just be drift risk for no benefit.
//
//  Photos are Storage download URLs (String), never embedded bytes —
//  PersonalCookbookPhotoUploadServicing uploads separately; this payload
//  only ever carries the resulting URL, the same division of labor
//  Publication/PublicationContentSnapshot already uses for shared-cookbook
//  photos.
//

import Foundation

/// `personalCookbooks/{cookbookID}` — one small doc per cookbook. Recipes
/// are a separate subcollection (PersonalCookbookRecipeDoc), not embedded
/// here, so a large cookbook never risks Firestore's 1MB document ceiling.
struct PersonalCookbookDoc: Codable {
    var id: UUID
    var ownerUserID: String
    var title: String
    var coverColorHex: String
    var coverStyleImageName: String?
    var coverImageURL: String?
    var sortOrder: Int
    var hasBeenConfigured: Bool
    var chaptersManuallyReordered: Bool
    var createdAt: Date
    var updatedAt: Date
    var chapters: [PersonalCookbookChapterDoc]
}

/// A chapter's id IS preserved (unlike CookbookSectionBackup's local-backup
/// counterpart, which also preserves it for the same within-archive
/// remapping reason) — here it's what PersonalCookbookRecipeDoc.sectionID
/// references directly, no remap step needed since sync keeps ids stable
/// end to end.
struct PersonalCookbookChapterDoc: Codable {
    var id: UUID
    var title: String
    var sortOrder: Int
}

/// `personalCookbooks/{cookbookID}/recipes/{recipeID}` — one doc per
/// recipe, full content. Field-for-field mirror of RecipeBackupPayload
/// minus the base64 photo fields (Storage URLs instead) plus `id`/
/// `ownerUserID`/`cookbookID` for stable identity and direct rule checks.
struct PersonalCookbookRecipeDoc: Codable {
    var id: UUID
    var ownerUserID: String
    var cookbookID: UUID
    var sectionID: UUID?

    var title: String
    var summary: String
    var story: String

    var heroPhotoURL: String?
    var galleryPhotoURLs: [String]

    var yield: String
    var prepTimeMinutes: Int?
    var cookTimeMinutes: Int?
    var totalTimeMinutes: Int?

    var ingredientSections: [IngredientSectionBackup]
    var stepSections: [StepSectionBackup]

    var notes: String
    var sourceType: RecipeSourceType
    var sourceURL: String?
    var sourceAuthorText: String?

    var externalSource: String?
    var externalSourceID: String?

    var calories: Double?
    var proteinGrams: Double?
    var fatGrams: Double?
    var carbsGrams: Double?
    var sugarGrams: Double?
    var fiberGrams: Double?
    var sodiumMilligrams: Double?

    var cuisine: String?
    var course: String?
    var dietaryLabels: [String]
    var allergens: [String]
    var tags: [String]
    var equipment: [String]

    var isFavorite: Bool
    var personalRating: Int?
    var privateNotes: String
    var isArchived: Bool

    var createdAt: Date
    var updatedAt: Date
    var language: String

    var rootOriginRecipeID: UUID?
    var immediateSourceRecipeID: UUID?
    var sourceOwnerSnapshot: String?
    var sourceGroupSnapshot: String?

    var authorLineage: String?
    var authorLineageIsExternal: Bool
    var inspirationCredit: String?
    var videoURLs: [String]
    var prepSummary: String?
}

/// Lightweight listing — id, title, updatedAt only — for the "Restore from
/// Cloud" picker and the post-sign-in "cookbooks available" detection.
/// Never fetches full recipe content just to show a list.
struct PersonalCookbookSummary: Identifiable {
    var id: UUID
    var title: String
    var updatedAt: Date
}
