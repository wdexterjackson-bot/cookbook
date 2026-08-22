//
//  PublicationContentSnapshotRecipeTests.swift
//  cookbookTests
//
//  Recipe -> PublicationContentSnapshot conversion. SwiftData @Model
//  objects can be constructed and read in-memory without a ModelContainer
//  as long as they're never inserted/queried — no persistence needed to
//  test pure mapping logic.
//

import Foundation
import Testing
@testable import cookbook

struct PublicationContentSnapshotRecipeTests {

    @Test func mapsTitleAndMetadataDirectly() {
        let recipe = Recipe(ownerID: "alice", title: "Skillet Cornbread", summary: "Crispy edges.", yield: "Serves 8")
        recipe.totalTimeMinutes = 40
        recipe.notes = "Best in a cast iron pan."
        recipe.tags = ["breakfast", "southern"]

        let snapshot = PublicationContentSnapshot.make(from: recipe)

        #expect(snapshot.title == "Skillet Cornbread")
        #expect(snapshot.summary == "Crispy edges.")
        #expect(snapshot.yield == "Serves 8")
        #expect(snapshot.totalTimeMinutes == 40)
        #expect(snapshot.notes == "Best in a cast iron pan.")
        #expect(snapshot.tags == ["breakfast", "southern"])
        #expect(snapshot.coverImageURL == nil)
        #expect(snapshot.authorLineage == nil)
    }

    @Test func mapsVideoURLsSoTheyTravelWithAPublishOrShare() {
        let recipe = Recipe(ownerID: "alice", title: "Skillet Cornbread")
        recipe.videoURLs = ["https://youtu.be/aaaaaaaaaaa", "https://youtu.be/bbbbbbbbbbb"]

        let snapshot = PublicationContentSnapshot.make(from: recipe)

        #expect(snapshot.videoURLs == ["https://youtu.be/aaaaaaaaaaa", "https://youtu.be/bbbbbbbbbbb"])
    }

    @Test func aRecipeWithNoVideosMapsToAnEmptyArrayNotNil() {
        let recipe = Recipe(ownerID: "alice", title: "Skillet Cornbread")

        let snapshot = PublicationContentSnapshot.make(from: recipe)

        #expect(snapshot.videoURLs == [])
    }

    @Test func mapsAuthorLineageWhenSet() {
        let recipe = Recipe(ownerID: "alice", title: "Cornbread")
        recipe.authorLineage = "Mary Jackson of Memphis, TN"

        let snapshot = PublicationContentSnapshot.make(from: recipe)

        #expect(snapshot.authorLineage == "Mary Jackson of Memphis, TN")
    }

    @Test func mapsIngredientAndStepSectionsInSortOrder() {
        let recipe = Recipe(ownerID: "alice", title: "Cornbread")

        let section = IngredientSection(heading: "Dry", sortOrder: 0)
        let flour = Ingredient(displayText: "2 cups flour", name: "flour", sortOrder: 1)
        let salt = Ingredient(displayText: "1 tsp salt", name: "salt", isOptional: true, sortOrder: 0)
        section.ingredients = [flour, salt]
        recipe.ingredientSections = [section]

        let steps = StepSection(heading: nil, sortOrder: 0)
        let second = Step(text: "Bake 20 minutes.", sortOrder: 1)
        let first = Step(text: "Preheat oven.", sortOrder: 0)
        steps.steps = [second, first]
        recipe.stepSections = [steps]

        let snapshot = PublicationContentSnapshot.make(from: recipe)

        #expect(snapshot.ingredientSections.count == 1)
        #expect(snapshot.ingredientSections[0].heading == "Dry")
        #expect(snapshot.ingredientSections[0].ingredients.map(\.displayText) == ["1 tsp salt", "2 cups flour"])
        #expect(snapshot.ingredientSections[0].ingredients[0].isOptional == true)

        #expect(snapshot.stepSections.count == 1)
        #expect(snapshot.stepSections[0].steps == ["Preheat oven.", "Bake 20 minutes."])
    }

    @Test func acceptsAnExplicitCoverImageURL() {
        let recipe = Recipe(ownerID: "alice", title: "Cornbread")

        let snapshot = PublicationContentSnapshot.make(from: recipe, coverImageURL: "https://example.com/photo.jpg")

        #expect(snapshot.coverImageURL == "https://example.com/photo.jpg")
    }

    // MARK: - Copy-to-Personal lineage (PRD §6)

    @Test func publishingAnOriginalRecipeSeedsItsOwnIDAsTheRootOrigin() {
        let recipe = Recipe(ownerID: "alice", title: "Alice's Cornbread")
        recipe.authorLineage = "Alice Barrentine of Memphis, TN"
        // No prior rootOriginRecipeID — this recipe was never copied from anywhere.

        let snapshot = PublicationContentSnapshot.make(from: recipe, groupName: "Memphis Family Barrentine")

        #expect(snapshot.rootOriginRecipeID == recipe.id.uuidString)
        #expect(snapshot.sourceOwnerSnapshot == "Alice Barrentine of Memphis, TN")
        #expect(snapshot.sourceGroupSnapshot == "Memphis Family Barrentine")
    }

    @Test func republishingAnAlreadyCopiedRecipePreservesTheTrueOriginalRoot() {
        let recipe = Recipe(ownerID: "carol", title: "Carol's Adapted Cornbread")
        recipe.authorLineage = "Carol Smith"
        // Carol's recipe is itself a copy — its root points at Alice's
        // original, not at Carol's own id.
        let aliceOriginalID = UUID()
        recipe.rootOriginRecipeID = aliceOriginalID

        let snapshot = PublicationContentSnapshot.make(from: recipe, groupName: "Cousins Group")

        // Root stays Alice's, even though Carol is republishing.
        #expect(snapshot.rootOriginRecipeID == aliceOriginalID.uuidString)
        // But the immediate source for whoever copies THIS publication is
        // Carol/Cousins Group, not Alice — computed fresh at this publish.
        #expect(snapshot.sourceOwnerSnapshot == "Carol Smith")
        #expect(snapshot.sourceGroupSnapshot == "Cousins Group")
    }

    @Test func groupNameDefaultsToNilForCallersThatDontPassOne() {
        let recipe = Recipe(ownerID: "alice", title: "Cornbread")

        let snapshot = PublicationContentSnapshot.make(from: recipe)

        #expect(snapshot.sourceGroupSnapshot == nil)
    }

    // ShareRecipeWithFriendView's attribution rule (see
    // attributingSenderIfUnattributed's own doc comment): sharing a
    // recipe that's a friend's own original creation (no prior lineage)
    // should credit the sender by name, not leave the recipient seeing
    // "You" for a recipe they didn't make.
    @Test func unattributedSnapshotGetsCreditedToTheSender() {
        let recipe = Recipe(ownerID: "alice", title: "Cornbread")
        let snapshot = PublicationContentSnapshot.make(from: recipe)
        #expect(snapshot.authorLineage == nil)

        let attributed = snapshot.attributingSenderIfUnattributed("Alice Alvarez")

        #expect(attributed.authorLineage == "Alice Alvarez")
        #expect(attributed.sourceOwnerSnapshot == "Alice Alvarez")
    }

    // The core "lineage must always stay intact" rule: a recipe that
    // already carries its own lineage (imported from Grandma, or copied
    // from someone else earlier) keeps that credit — the sender sharing
    // it is never substituted in, even though the sender is the one who
    // triggered this particular share.
    @Test func existingLineageSurvivesASharePreservingTheOriginalCredit() {
        let recipe = Recipe(ownerID: "alice", title: "Tamales")
        recipe.authorLineage = "Abuela Rosa"
        let snapshot = PublicationContentSnapshot.make(from: recipe)

        let attributed = snapshot.attributingSenderIfUnattributed("Alice Alvarez")

        #expect(attributed.authorLineage == "Abuela Rosa")
    }

    @Test func aNilSenderNameLeavesAnUnattributedSnapshotStillUnattributed() {
        let recipe = Recipe(ownerID: "alice", title: "Cornbread")
        let snapshot = PublicationContentSnapshot.make(from: recipe)

        let attributed = snapshot.attributingSenderIfUnattributed(nil)

        #expect(attributed.authorLineage == nil)
    }
}
