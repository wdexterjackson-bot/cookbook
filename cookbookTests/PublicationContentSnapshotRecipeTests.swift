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
}
