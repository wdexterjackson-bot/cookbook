//
//  cookbookApp.swift
//  cookbook
//
//  Created by Dexter Jackson on 8/5/26.
//

import SwiftUI
import SwiftData

@main
struct cookbookApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Recipe.self,
            IngredientSection.self,
            Ingredient.self,
            StepSection.self,
            Step.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RecipeListView()
        }
        .modelContainer(sharedModelContainer)
    }
}
