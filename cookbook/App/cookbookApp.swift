//
//  cookbookApp.swift
//  cookbook
//
//  Created by Dexter Jackson on 8/5/26.
//

import SwiftUI
import SwiftData
import FirebaseCore
#if os(iOS)
import GoogleSignIn
#endif

@main
struct cookbookApp: App {
    var sharedModelContainer: ModelContainer
    @State private var accountState: AccountState

    init() {
        FirebaseApp.configure()

        let schema = Schema([
            Recipe.self,
            IngredientSection.self,
            Ingredient.self,
            StepSection.self,
            Step.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            sharedModelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }

        _accountState = State(initialValue: AccountState(authService: FirebaseAuthService()))
    }

    var body: some Scene {
        WindowGroup {
            RecipeListView()
                #if os(iOS)
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
                #endif
        }
        .modelContainer(sharedModelContainer)
        .environment(accountState)
    }
}
