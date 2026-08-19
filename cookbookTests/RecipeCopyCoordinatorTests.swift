//
//  RecipeCopyCoordinatorTests.swift
//  cookbookTests
//

import Foundation
import SwiftData
import Testing
@testable import cookbook

struct RecipeCopyCoordinatorTests {

    private func makeInMemoryContext() throws -> ModelContext {
        let schema = Schema([
            Recipe.self, IngredientSection.self, Ingredient.self, StepSection.self, Step.self,
            Cookbook.self, CookbookSection.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    private func makeTargetCookbook(ownerID: String = "bob") -> Cookbook {
        Cookbook(ownerID: ownerID, title: "Bob's Cookbook")
    }

    private func makePublication(
        sourceRecipeID: String = UUID().uuidString,
        title: String = "Abuela's Tamales",
        authorLineage: String? = "Dante Ruiz",
        rootOriginRecipeID: String? = nil,
        sourceOwnerSnapshot: String? = "Dante Ruiz",
        sourceGroupSnapshot: String? = "The Alvarez Family Table"
    ) -> Publication {
        let content = PublicationContentSnapshot(
            title: title,
            summary: "A holiday favorite.",
            yield: "Serves 8",
            totalTimeMinutes: 90,
            ingredientSections: [
                PublicationIngredientSection(heading: nil, ingredients: [
                    PublicationIngredient(displayText: "2 cups masa harina", isOptional: false),
                    PublicationIngredient(displayText: "1 cup broth, optional", isOptional: true),
                ]),
            ],
            stepSections: [
                PublicationStepSection(heading: nil, steps: ["Mix the masa.", "Steam for 90 minutes."]),
            ],
            notes: "Freezes well.",
            tags: ["holiday"],
            authorLineage: authorLineage,
            rootOriginRecipeID: rootOriginRecipeID,
            sourceOwnerSnapshot: sourceOwnerSnapshot,
            sourceGroupSnapshot: sourceGroupSnapshot
        )
        return Publication(
            id: "pub-1", groupID: "group-1", cookbookID: "cb-1", ownerUserID: "dante",
            sourceRecipeID: sourceRecipeID, state: .published, publishedAt: .now, updatedAt: .now, content: content
        )
    }

    @Test func copyCreatesAnIndependentlyOwnedRecipeWithFullContent() throws {
        let context = try makeInMemoryContext()
        let cookbook = makeTargetCookbook()
        context.insert(cookbook)
        let publication = makePublication()

        let result = RecipeCopyCoordinator.copy(publication, forUserID: "bob", into: cookbook, modelContext: context)

        guard case .success(let recipe) = result else {
            Issue.record("expected a successful copy")
            return
        }
        #expect(recipe.ownerID == "bob")
        #expect(recipe.cookbookID == cookbook.id)
        #expect(recipe.title == "Abuela's Tamales")
        #expect(recipe.notes == "Freezes well.")
        #expect(recipe.tags == ["holiday"])
        let ingredients = recipe.ingredientSections.first?.ingredients.sorted { $0.sortOrder < $1.sortOrder } ?? []
        #expect(ingredients.map(\.displayText) == ["2 cups masa harina", "1 cup broth, optional"])
        let steps = recipe.stepSections.first?.steps.sorted { $0.sortOrder < $1.sortOrder } ?? []
        #expect(steps.map(\.text) == ["Mix the masa.", "Steam for 90 minutes."])
        #expect(recipe.authorLineage == "Dante Ruiz")
        #expect(recipe.authorLineageIsExternal == true)
    }

    @Test func copyingAnOriginalPublicationSetsRootEqualToImmediateSource() throws {
        let context = try makeInMemoryContext()
        let cookbook = makeTargetCookbook()
        context.insert(cookbook)
        let sourceRecipeID = UUID()
        // No rootOriginRecipeID on the content — Dante's tamale recipe was
        // an original, never itself a copy.
        let publication = makePublication(sourceRecipeID: sourceRecipeID.uuidString, rootOriginRecipeID: nil)

        let result = RecipeCopyCoordinator.copy(publication, forUserID: "bob", into: cookbook, modelContext: context)

        guard case .success(let recipe) = result else {
            Issue.record("expected a successful copy")
            return
        }
        #expect(recipe.immediateSourceRecipeID == sourceRecipeID)
        #expect(recipe.rootOriginRecipeID == sourceRecipeID)
    }

    @Test func copyingAnAlreadyCopiedPublicationPreservesTheTrueOriginalRootNotTheImmediateParent() throws {
        let context = try makeInMemoryContext()
        let cookbook = makeTargetCookbook()
        context.insert(cookbook)
        let immediateSourceRecipeID = UUID() // Carol's own recipe id, published to Cousins Group
        let trueRootID = UUID() // Alice's original, several hops back
        let publication = makePublication(
            sourceRecipeID: immediateSourceRecipeID.uuidString,
            rootOriginRecipeID: trueRootID.uuidString,
            sourceOwnerSnapshot: "Carol Smith",
            sourceGroupSnapshot: "Cousins Group"
        )

        let result = RecipeCopyCoordinator.copy(publication, forUserID: "dan", into: cookbook, modelContext: context)

        guard case .success(let recipe) = result else {
            Issue.record("expected a successful copy")
            return
        }
        #expect(recipe.immediateSourceRecipeID == immediateSourceRecipeID)
        #expect(recipe.rootOriginRecipeID == trueRootID)
        #expect(recipe.rootOriginRecipeID != immediateSourceRecipeID)
        #expect(recipe.sourceOwnerSnapshot == "Carol Smith")
        #expect(recipe.sourceGroupSnapshot == "Cousins Group")
    }

    @Test func theCopyIsIndependentlyEditableAndDoesNotMutateThePublicationsOwnData() throws {
        let context = try makeInMemoryContext()
        let cookbook = makeTargetCookbook()
        context.insert(cookbook)
        let publication = makePublication()

        let result = RecipeCopyCoordinator.copy(publication, forUserID: "bob", into: cookbook, modelContext: context)
        guard case .success(let recipe) = result else {
            Issue.record("expected a successful copy")
            return
        }
        recipe.title = "Bob's Tweaked Tamales"
        try context.save()

        #expect(recipe.title == "Bob's Tweaked Tamales")
        #expect(publication.content.title == "Abuela's Tamales") // untouched
        #expect(recipe.ownerID != publication.ownerUserID)
    }
}
