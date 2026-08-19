//
//  Publication.swift
//  cookbook
//
//  Publications carry a full content snapshot, not a reference to a local
//  Recipe — personal recipes stay in SwiftData on the owner's device only
//  (Phase 2 scope decision), so Firestore is the only place other group
//  members can actually read a published recipe's content from.
//

import Foundation

enum PublicationState: String, Codable {
    case published
    case unpublished
    case hidden
}

struct PublicationIngredient: Codable, Equatable {
    var displayText: String
    var isOptional: Bool
}

struct PublicationIngredientSection: Codable, Equatable {
    var heading: String?
    var ingredients: [PublicationIngredient]
}

struct PublicationStepSection: Codable, Equatable {
    var heading: String?
    var steps: [String]
}

struct PublicationContentSnapshot: Codable, Equatable {
    var title: String
    var summary: String
    var yield: String
    var totalTimeMinutes: Int?
    var ingredientSections: [PublicationIngredientSection]
    var stepSections: [PublicationStepSection]
    var notes: String
    var tags: [String]
    /// Firebase Storage download URL for the recipe's hero photo, if it
    /// had one and the upload succeeded. Nil is a normal, expected state
    /// (text-only recipe, or a non-fatal upload failure) — never required.
    var coverImageURL: String?
    /// "FName LName of City, ST" (or "Anonymous") — the source Recipe's
    /// immutable author lineage, carried through so other group members
    /// see who a published recipe is credited to. Nil for recipes
    /// published before this field existed.
    var authorLineage: String?
    /// Copy-to-Personal lineage (PRD §6), snapshotted from the source
    /// Recipe at publish time — not derived at copy time, so a chain of
    /// copies (Alice → Bob → this group → Carol) preserves the *true*
    /// original root rather than resetting to "immediate parent" at every
    /// hop. `rootOriginRecipeID` is the earliest known recipe in the chain
    /// (== Publication.sourceRecipeID when the source Recipe was itself an
    /// original, i.e. had no prior lineage of its own); `sourceOwnerSnapshot`/
    /// `sourceGroupSnapshot` describe where *this* immediate copy came
    /// from. All nil for publications created before Copy-to-Personal
    /// existed.
    var rootOriginRecipeID: String?
    var sourceOwnerSnapshot: String?
    var sourceGroupSnapshot: String?

    init(
        title: String,
        summary: String,
        yield: String,
        totalTimeMinutes: Int?,
        ingredientSections: [PublicationIngredientSection],
        stepSections: [PublicationStepSection],
        notes: String,
        tags: [String],
        coverImageURL: String? = nil,
        authorLineage: String? = nil,
        rootOriginRecipeID: String? = nil,
        sourceOwnerSnapshot: String? = nil,
        sourceGroupSnapshot: String? = nil
    ) {
        self.title = title
        self.summary = summary
        self.yield = yield
        self.totalTimeMinutes = totalTimeMinutes
        self.ingredientSections = ingredientSections
        self.stepSections = stepSections
        self.notes = notes
        self.tags = tags
        self.coverImageURL = coverImageURL
        self.authorLineage = authorLineage
        self.rootOriginRecipeID = rootOriginRecipeID
        self.sourceOwnerSnapshot = sourceOwnerSnapshot
        self.sourceGroupSnapshot = sourceGroupSnapshot
    }
}

struct Publication: Codable, Identifiable, Equatable {
    var id: String
    var groupID: String
    /// Which of the group's (possibly several) cookbooks this belongs to
    /// — required, no nil-handling, since this field didn't exist before
    /// the #5 clean-slate data wipe (see firestore.rules' publications/
    /// create rule, which checks this belongs to the claimed groupID).
    var cookbookID: String
    var ownerUserID: String
    /// The local SwiftData Recipe.id this was published from — what makes
    /// "publish this recipe again" update the existing Publication in
    /// place (LIN-001) instead of creating a duplicate, and what a copier's
    /// immediateSourceRecipeID lineage field points back at.
    var sourceRecipeID: String
    var state: PublicationState
    var publishedAt: Date
    var updatedAt: Date
    var content: PublicationContentSnapshot
    /// Nil for publications created before like-counting existed — treat
    /// as 0 (see the `?? 0` at GroupCookbookView's display site). Inline
    /// `= nil` so existing Publication(...) call sites don't need updating
    /// and old Firestore docs lacking the field still decode. Maintained
    /// by PublicationsServicing.setLiked, paired (same transaction) with a
    /// publications/{id}/likes/{userID} doc marking who's liked it — that
    /// subcollection is what makes "did I already like this" and the
    /// increment/decrement idempotent per user.
    var likeCount: Int? = nil
    /// Same nil-tolerant/denormalized pattern as likeCount, for a 1-5 star
    /// rating system rather than a binary like — average is computed on
    /// read (ratingSum / ratingCount) rather than stored, so it can never
    /// drift from the underlying counts. Maintained by
    /// PublicationsServicing.setRating/clearRating, paired (same
    /// transaction) with a publications/{id}/ratings/{userID} doc holding
    /// that user's own 1-5 value — unlike likes, a rating can be *changed*
    /// (not just toggled), so that subcollection allows update, not just
    /// create/delete.
    var ratingSum: Int? = nil
    var ratingCount: Int? = nil
    /// Off by default — set via the publish flow's "Allow Comments?"
    /// toggle. The whole comment list (RecipeComment) is gated on this at
    /// read time rather than each comment carrying its own visibility.
    var commentsEnabled: Bool = false
}

extension Publication {
    /// One publication document per (group, cookbook, source recipe,
    /// owner) tuple, id'd deterministically rather than by a random UUID —
    /// closes a check-then-act race where two concurrent publish() calls
    /// for the same recipe (a double-tap, or a retry after an ambiguous
    /// network response) could each miss the other's write and create two
    /// separate, duplicate publication docs. With a deterministic ID, both
    /// calls converge on the same document — worst case is a harmless
    /// last-write-wins overwrite, never a duplicate.
    static func compositeID(groupID: String, cookbookID: String, sourceRecipeID: String, ownerUserID: String) -> String {
        "\(groupID)_\(cookbookID)_\(sourceRecipeID)_\(ownerUserID)"
    }
}
