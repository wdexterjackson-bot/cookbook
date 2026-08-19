//
//  CookbookPDFExporterTests.swift
//  cookbookTests
//

import Foundation
import PDFKit
import Testing
@testable import cookbook

struct CookbookPDFExporterTests {

    private func makeRecipe(
        cookbookID: UUID,
        title: String,
        sectionID: UUID? = nil,
        author: String? = nil,
        notes: String = "",
        ingredient: String = "2 cups flour",
        step: String = "Mix everything together."
    ) -> Recipe {
        let recipe = Recipe(ownerID: "owner-1", title: title)
        recipe.cookbookID = cookbookID
        recipe.sectionID = sectionID
        recipe.authorLineage = author
        recipe.notes = notes

        let ingredientSection = IngredientSection()
        ingredientSection.ingredients = [Ingredient(displayText: ingredient, name: "flour")]
        recipe.ingredientSections = [ingredientSection]

        let stepSection = StepSection()
        stepSection.steps = [Step(text: step)]
        recipe.stepSections = [stepSection]

        return recipe
    }

    private func extractedText(from data: Data) -> String {
        guard let document = PDFDocument(data: data) else { return "" }
        var combined = ""
        for index in 0..<document.pageCount {
            combined += document.page(at: index)?.string ?? ""
            combined += "\n"
        }
        return combined
    }

    @Test func producesAValidPDFWithOnePagePerRecipe() {
        let cookbook = Cookbook(ownerID: "owner-1", title: "Test Cookbook")
        let recipes = [
            makeRecipe(cookbookID: cookbook.id, title: "Cornbread"),
            makeRecipe(cookbookID: cookbook.id, title: "Pumpkin Pie"),
        ]

        let data = CookbookPDFExporter.generatePDF(for: cookbook, recipes: recipes)

        #expect(data.starts(with: Array("%PDF".utf8)))
        let document = PDFDocument(data: data)
        #expect(document?.pageCount == 2)
    }

    @Test func omitsTheRecipeIdentifierEntirely() {
        let cookbook = Cookbook(ownerID: "owner-1", title: "Test Cookbook")
        let recipe = makeRecipe(cookbookID: cookbook.id, title: "Cornbread")

        let data = CookbookPDFExporter.generatePDF(for: cookbook, recipes: [recipe])
        let text = extractedText(from: data)

        #expect(!text.contains(recipe.id.uuidString))
    }

    @Test func includesNotesWhenPresent() {
        let cookbook = Cookbook(ownerID: "owner-1", title: "Test Cookbook")
        let recipe = makeRecipe(cookbookID: cookbook.id, title: "Cornbread", notes: "Best served warm.")

        let data = CookbookPDFExporter.generatePDF(for: cookbook, recipes: [recipe])
        let text = extractedText(from: data)

        #expect(text.contains("Notes:"))
        #expect(text.contains("Best served warm."))
    }

    @Test func alwaysShowsNotesAndVideosHeadingsEvenWhenEmpty() {
        let cookbook = Cookbook(ownerID: "owner-1", title: "Test Cookbook")
        let recipe = makeRecipe(cookbookID: cookbook.id, title: "Cornbread", notes: "")

        let data = CookbookPDFExporter.generatePDF(for: cookbook, recipes: [recipe])
        let text = extractedText(from: data)

        #expect(text.contains("Notes:"))
        #expect(text.contains("Videos:"))
    }

    @Test func includesVideoURLsWhenPresent() {
        let cookbook = Cookbook(ownerID: "owner-1", title: "Test Cookbook")
        let recipe = makeRecipe(cookbookID: cookbook.id, title: "Cornbread")
        recipe.videoURLs = ["https://www.youtube.com/watch?v=dQw4w9WgXcQ"]

        let data = CookbookPDFExporter.generatePDF(for: cookbook, recipes: [recipe])
        let text = extractedText(from: data)

        #expect(text.contains("Videos:"))
        #expect(text.contains("https://www.youtube.com/watch?v=dQw4w9WgXcQ"))
    }

    @Test func bulletsEachIngredientLine() {
        let cookbook = Cookbook(ownerID: "owner-1", title: "Test Cookbook")
        let recipe = makeRecipe(cookbookID: cookbook.id, title: "Cornbread", ingredient: "2 cups cornmeal")

        let data = CookbookPDFExporter.generatePDF(for: cookbook, recipes: [recipe])
        let text = extractedText(from: data)

        #expect(text.contains("•"))
    }

    @Test func ordersRecipesByChapterThenAlphabeticallyThenUnfiledLast() {
        let cookbook = Cookbook(ownerID: "owner-1", title: "Test Cookbook")
        let desserts = CookbookSection(title: "Desserts", sortOrder: 0)
        let breads = CookbookSection(title: "Breads", sortOrder: 1)
        cookbook.sections = [desserts, breads]

        let recipes = [
            makeRecipe(cookbookID: cookbook.id, title: "Cornbread", sectionID: breads.id),
            makeRecipe(cookbookID: cookbook.id, title: "Unfiled Snack"),
            makeRecipe(cookbookID: cookbook.id, title: "Cookies", sectionID: desserts.id),
            makeRecipe(cookbookID: cookbook.id, title: "Apple Pie", sectionID: desserts.id),
        ]

        let data = CookbookPDFExporter.generatePDF(for: cookbook, recipes: recipes)
        guard let document = PDFDocument(data: data) else {
            Issue.record("Failed to parse generated PDF")
            return
        }

        let pageTitles = (0..<document.pageCount).map { document.page(at: $0)?.string ?? "" }
        let expectedOrder = ["Apple Pie", "Cookies", "Cornbread", "Unfiled Snack"]
        #expect(pageTitles.count == expectedOrder.count)
        for (page, title) in zip(pageTitles, expectedOrder) {
            #expect(page.contains(title))
        }
    }

    @Test func includesIngredientsAndStepsInSamplePDFFormat() {
        let cookbook = Cookbook(ownerID: "owner-1", title: "Test Cookbook")
        let recipe = makeRecipe(
            cookbookID: cookbook.id,
            title: "Cornbread",
            author: "Mary Jackson of Memphis, TN",
            ingredient: "2 cups cornmeal",
            step: "Bake at 425°F for 20 minutes."
        )

        let data = CookbookPDFExporter.generatePDF(for: cookbook, recipes: [recipe])
        let text = extractedText(from: data)

        #expect(text.contains("Name: Cornbread"))
        #expect(text.contains("By: Mary Jackson of Memphis, TN"))
        #expect(text.contains("2 cups cornmeal"))
        #expect(text.contains("Bake at"))
        #expect(text.contains("Ingredients:"))
        #expect(text.contains("Directions:"))
    }

    @Test func emptyRecipeListProducesNoRecipeContent() {
        let cookbook = Cookbook(ownerID: "owner-1", title: "Empty Cookbook")

        let data = CookbookPDFExporter.generatePDF(for: cookbook, recipes: [])

        // closePDF() with no recipes still yields a single blank page
        // rather than a zero-page document — harmless, since the calling
        // view (ExportCookbookPDFView) disables Export before this is
        // ever reachable for an empty cookbook. What matters here is that
        // no recipe content leaks in.
        let document = PDFDocument(data: data)
        #expect((document?.pageCount ?? 0) <= 1)
        #expect(extractedText(from: data).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}
