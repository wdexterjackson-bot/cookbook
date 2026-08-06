//
//  RecipeLineImportServicingTests.swift
//  cookbookTests
//
//  Against the fake only — the real adapter needs Apple Intelligence
//  actually running, which isn't something a unit test suite should
//  depend on (same reasoning as keeping live network calls out of
//  MealSearchServicingTests).
//

import Foundation
import Testing
@testable import cookbook

struct RecipeLineImportServicingTests {

    @Test func parsesTextIntoStubbedResult() async throws {
        let service = FakeRecipeLineImportService()
        service.stubbedResult = ParsedRecipeLines(
            ingredients: [ParsedIngredientLine(name: "flour", quantity: 2, unit: "cup")],
            steps: ["Preheat the oven."]
        )

        let result = try await service.parseLines(from: "2 cups flour\nPreheat the oven.")

        #expect(result.ingredients == [ParsedIngredientLine(name: "flour", quantity: 2, unit: "cup")])
        #expect(result.steps == ["Preheat the oven."])
        #expect(service.lastParsedText == "2 cups flour\nPreheat the oven.")
    }

    @Test func parsesTitleChapterAuthorAndNotesFromStubbedResult() async throws {
        let service = FakeRecipeLineImportService()
        service.stubbedResult = ParsedRecipeLines(
            title: "Skillet Cornbread",
            chapterName: "Desserts",
            ingredients: [],
            steps: [],
            notes: "Feeds 6-8.",
            authorLineageText: "Jane Doe of Baltimore, MD"
        )

        let result = try await service.parseLines(from: "Name: Skillet Cornbread")

        #expect(result.title == "Skillet Cornbread")
        #expect(result.chapterName == "Desserts")
        #expect(result.notes == "Feeds 6-8.")
        #expect(result.authorLineageText == "Jane Doe of Baltimore, MD")
    }

    @Test func throwsOnEmptyInput() async throws {
        let service = FakeRecipeLineImportService()

        await #expect(throws: RecipeLineImportError.emptyInput) {
            try await service.parseLines(from: "   ")
        }
    }

    @Test func throwsWhenUnavailable() async throws {
        let service = FakeRecipeLineImportService()
        service.isAvailable = false

        await #expect(throws: RecipeLineImportError.unavailable) {
            try await service.parseLines(from: "2 cups flour")
        }
    }
}
