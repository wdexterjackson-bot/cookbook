//
//  CookbookBackupServiceTests.swift
//  cookbookTests
//

import Foundation
import SwiftData
import Testing
@testable import cookbook

struct CookbookBackupServiceTests {

    private func makeInMemoryContext() throws -> ModelContext {
        let schema = Schema([
            Recipe.self, IngredientSection.self, Ingredient.self, StepSection.self, Step.self,
            Cookbook.self, CookbookSection.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    /// A cookbook with one chapter and one fully-populated recipe filed
    /// into it, plus an unfiled recipe — enough surface area to exercise
    /// chapter remapping, ingredient/step round-tripping, and "Other".
    private func makeSampleCookbook(in context: ModelContext, ownerID: String) throws -> (Cookbook, [Recipe]) {
        let cookbook = Cookbook(ownerID: ownerID, title: "Grandma's Kitchen", coverColorHex: "C25432")
        cookbook.hasBeenConfigured = true
        cookbook.chaptersManuallyReordered = true
        context.insert(cookbook)

        let chapter = CookbookSection(title: "Appetizers", sortOrder: 0)
        cookbook.sections = [chapter]

        let filedRecipe = Recipe(ownerID: ownerID, title: "Sausage Balls", summary: "Party classic", yield: "Serves 12")
        filedRecipe.cookbookID = cookbook.id
        filedRecipe.sectionID = chapter.id
        filedRecipe.tags = ["party", "pork"]
        filedRecipe.isFavorite = true
        filedRecipe.personalRating = 5
        filedRecipe.authorLineage = "Mary Jackson of Memphis, TN"
        filedRecipe.calories = 210

        let ingredientSection = IngredientSection(heading: nil, sortOrder: 0)
        ingredientSection.ingredients = [
            Ingredient(displayText: "1 lb sausage", name: "sausage", quantityValue: 1, unit: "lb", sortOrder: 0),
            Ingredient(displayText: "2 cups baking mix", name: "baking mix", quantityValue: 2, unit: "cups", sortOrder: 1),
        ]
        filedRecipe.ingredientSections = [ingredientSection]

        let stepSection = StepSection(heading: nil, sortOrder: 0)
        stepSection.steps = [
            Step(text: "Mix everything together.", sortOrder: 0),
            Step(text: "Bake at 350°F for 20 minutes.", sortOrder: 1),
        ]
        filedRecipe.stepSections = [stepSection]

        let unfiledRecipe = Recipe(ownerID: ownerID, title: "Unfiled Recipe")
        unfiledRecipe.cookbookID = cookbook.id

        context.insert(filedRecipe)
        context.insert(unfiledRecipe)
        try context.save()

        return (cookbook, [filedRecipe, unfiledRecipe])
    }

    @Test func exportThenRestoreRoundTripsCookbookMetadata() throws {
        let context = try makeInMemoryContext()
        let (cookbook, recipes) = try makeSampleCookbook(in: context, ownerID: "alice")

        let data = try CookbookBackupService.exportData(for: cookbook, recipes: recipes)
        let restored = try CookbookBackupService.restore(data, ownerID: "alice", modelContext: context)

        #expect(restored.title == "Grandma's Kitchen")
        #expect(restored.coverColorHex == "C25432")
        #expect(restored.hasBeenConfigured == true)
        #expect(restored.chaptersManuallyReordered == true)
        #expect(restored.id != cookbook.id)
    }

    @Test func exportThenRestoreRoundTripsChaptersAndRecipeAssignment() throws {
        let context = try makeInMemoryContext()
        let (cookbook, recipes) = try makeSampleCookbook(in: context, ownerID: "alice")

        let data = try CookbookBackupService.exportData(for: cookbook, recipes: recipes)
        let restored = try CookbookBackupService.restore(data, ownerID: "alice", modelContext: context)

        #expect(restored.sections.count == 1)
        #expect(restored.sections.first?.title == "Appetizers")
        #expect(restored.sections.first?.id != cookbook.sections.first?.id)

        let descriptor = FetchDescriptor<Recipe>(predicate: #Predicate<Recipe> { $0.title == "Sausage Balls" })
        let restoredFiled = try #require(try context.fetch(descriptor).first { $0.cookbookID == restored.id })
        #expect(restoredFiled.sectionID == restored.sections.first?.id)

        let unfiledDescriptor = FetchDescriptor<Recipe>(predicate: #Predicate<Recipe> { $0.title == "Unfiled Recipe" })
        let restoredUnfiled = try #require(try context.fetch(unfiledDescriptor).first { $0.cookbookID == restored.id })
        #expect(restoredUnfiled.sectionID == nil)
    }

    @Test func exportThenRestoreRoundTripsIngredientsAndSteps() throws {
        let context = try makeInMemoryContext()
        let (cookbook, recipes) = try makeSampleCookbook(in: context, ownerID: "alice")

        let data = try CookbookBackupService.exportData(for: cookbook, recipes: recipes)
        let restored = try CookbookBackupService.restore(data, ownerID: "alice", modelContext: context)

        let descriptor = FetchDescriptor<Recipe>(predicate: #Predicate<Recipe> { $0.title == "Sausage Balls" })
        let restoredRecipe = try #require(try context.fetch(descriptor).first { $0.cookbookID == restored.id })

        #expect(restoredRecipe.tags == ["party", "pork"])
        #expect(restoredRecipe.isFavorite == true)
        #expect(restoredRecipe.personalRating == 5)
        #expect(restoredRecipe.authorLineage == "Mary Jackson of Memphis, TN")
        #expect(restoredRecipe.calories == 210)

        let ingredients = restoredRecipe.ingredientSections.first?.ingredients.sorted { $0.sortOrder < $1.sortOrder } ?? []
        #expect(ingredients.map(\.name) == ["sausage", "baking mix"])

        let steps = restoredRecipe.stepSections.first?.steps.sorted { $0.sortOrder < $1.sortOrder } ?? []
        #expect(steps.map(\.text) == ["Mix everything together.", "Bake at 350°F for 20 minutes."])
    }

    @Test func exportThenRestoreRoundTripsCoverAndHeroPhotos() throws {
        let context = try makeInMemoryContext()
        let (cookbook, recipes) = try makeSampleCookbook(in: context, ownerID: "alice")

        let coverData = Data([0x01, 0x02, 0x03])
        cookbook.coverImageFilename = try PhotoStore.save(coverData)
        let heroData = Data([0x04, 0x05, 0x06])
        recipes[0].heroPhotoFilename = try PhotoStore.save(heroData)
        try context.save()
        defer {
            PhotoStore.delete(cookbook.coverImageFilename!)
            PhotoStore.delete(recipes[0].heroPhotoFilename!)
        }

        let data = try CookbookBackupService.exportData(for: cookbook, recipes: recipes)
        let restored = try CookbookBackupService.restore(data, ownerID: "alice", modelContext: context)
        defer {
            if let filename = restored.coverImageFilename { PhotoStore.delete(filename) }
        }

        let restoredCoverFilename = try #require(restored.coverImageFilename)
        #expect(PhotoStore.data(for: restoredCoverFilename) == coverData)
        #expect(restoredCoverFilename != cookbook.coverImageFilename)

        let descriptor = FetchDescriptor<Recipe>(predicate: #Predicate<Recipe> { $0.title == "Sausage Balls" })
        let restoredRecipe = try #require(try context.fetch(descriptor).first { $0.cookbookID == restored.id })
        let restoredHeroFilename = try #require(restoredRecipe.heroPhotoFilename)
        defer { PhotoStore.delete(restoredHeroFilename) }
        #expect(PhotoStore.data(for: restoredHeroFilename) == heroData)
    }

    @Test func restoreAlwaysCreatesANewCookbookRatherThanCollidingWithAnExisting() throws {
        let context = try makeInMemoryContext()
        let (cookbook, recipes) = try makeSampleCookbook(in: context, ownerID: "alice")
        let data = try CookbookBackupService.exportData(for: cookbook, recipes: recipes)

        // Restoring the SAME backup twice, with the original cookbook still
        // present, must never collide — three independent cookbooks total.
        _ = try CookbookBackupService.restore(data, ownerID: "alice", modelContext: context)
        _ = try CookbookBackupService.restore(data, ownerID: "alice", modelContext: context)

        let descriptor = FetchDescriptor<Cookbook>(predicate: #Predicate<Cookbook> { $0.title == "Grandma's Kitchen" })
        #expect(try context.fetch(descriptor).count == 3)
    }

    @Test func restoreIsResilientToACorruptEmbeddedPhoto() throws {
        let context = try makeInMemoryContext()
        let (cookbook, recipes) = try makeSampleCookbook(in: context, ownerID: "alice")
        var data = try CookbookBackupService.exportData(for: cookbook, recipes: recipes)

        // Hand-corrupt the JSON's heroPhotoBase64-shaped content is brittle
        // to simulate at the byte level, so instead prove resilience the
        // way it actually happens: decode, poison one payload's field with
        // non-base64 text, re-encode, then restore — the recipe itself
        // must still come through with everything else intact.
        var archive = try CookbookBackupService.jsonDecoder.decode(CookbookBackupArchive.self, from: data)
        archive.cookbook.recipes[0].heroPhotoBase64 = "not valid base64!!"
        data = try CookbookBackupService.jsonEncoder.encode(archive)

        let restored = try CookbookBackupService.restore(data, ownerID: "alice", modelContext: context)

        let descriptor = FetchDescriptor<Recipe>(predicate: #Predicate<Recipe> { $0.title == "Sausage Balls" })
        let restoredRecipe = try #require(try context.fetch(descriptor).first { $0.cookbookID == restored.id })
        #expect(restoredRecipe.heroPhotoFilename == nil)
    }

    // MARK: - Forward-compatibility guard rail

    /// The @Model macro backs each `var foo` with a stored `_foo` (plus
    /// framework-internal `_$`-prefixed Observation/SwiftData machinery
    /// that isn't a real model field at all) — Mirror sees that backing
    /// storage, not the plain property name, so this normalizes both away.
    /// A no-op for the payload structs' own Mirror labels, which are
    /// already plain (they're not @Model types).
    private func storedPropertyNames(of instance: Any) -> Set<String> {
        Set(Mirror(reflecting: instance).children.compactMap { child -> String? in
            guard let label = child.label else { return nil }
            if label.hasPrefix("_$") { return nil }
            return label.hasPrefix("_") ? String(label.dropFirst()) : label
        })
    }

    /// Fails loudly if Recipe gains a stored property that RecipeBackupPayload
    /// doesn't know about (by name, or by one of the deliberate renames/
    /// exclusions documented in CookbookBackupArchive.swift's header) —
    /// see that file's comment for why this exists.
    @Test func recipeBackupPayloadTracksEveryRecipeStoredProperty() {
        let sample = Recipe(ownerID: "owner", title: "Sample")
        let recipeProperties = storedPropertyNames(of: sample)

        let samplePayload = RecipeBackupPayload(
            recipe: sample,
            heroPhotoBase64: nil,
            galleryPhotoBase64: [],
            ingredientSections: [],
            stepSections: []
        )
        let payloadProperties = storedPropertyNames(of: samplePayload)

        let deliberatelyExcludedOrRenamed: Set<String> = [
            "id", "ownerID", "cookbookID",   // restore-time-determined, never backed up
            "sectionID",                      // -> originalSectionID
            "heroPhotoFilename",               // -> heroPhotoBase64
            "galleryPhotoFilenames",           // -> galleryPhotoBase64
        ]

        let uncovered = recipeProperties.subtracting(payloadProperties).subtracting(deliberatelyExcludedOrRenamed)
        #expect(uncovered.isEmpty, "Recipe gained propert(y/ies) not represented in RecipeBackupPayload: \(uncovered.sorted())")
    }

    @Test func cookbookBackupPayloadTracksEveryCookbookStoredProperty() {
        let sample = Cookbook(ownerID: "owner", title: "Sample")
        let cookbookProperties = storedPropertyNames(of: sample)

        let samplePayload = CookbookBackupPayload(cookbook: sample, coverImageBase64: nil, recipes: [])
        let payloadProperties = storedPropertyNames(of: samplePayload)

        let deliberatelyExcludedOrRenamed: Set<String> = [
            "id", "ownerID",       // restore-time-determined, never backed up
            "coverImageFilename",  // -> coverImageBase64
            "sortOrder",           // restored cookbook uses the same default as any newly created one
            "updatedAt",           // stamped fresh at restore
            "sections",            // -> chapters
        ]

        let uncovered = cookbookProperties.subtracting(payloadProperties).subtracting(deliberatelyExcludedOrRenamed)
        #expect(uncovered.isEmpty, "Cookbook gained propert(y/ies) not represented in CookbookBackupPayload: \(uncovered.sorted())")
    }
}
