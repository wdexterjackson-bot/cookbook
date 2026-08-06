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
    @State private var activeCookbookState = ActiveCookbookState()
    @State private var cookingSessionState = CookingSessionState()

    init() {
        FirebaseApp.configure()

        let schema = Schema([
            Recipe.self,
            IngredientSection.self,
            Ingredient.self,
            StepSection.self,
            Step.self,
            Cookbook.self,
            CookbookSection.self,
            CartItem.self,
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
            AuthGatedRootView()
                #if os(iOS)
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
                #endif
                // Sketch C "Potluck" has no dark-mode variant — screens
                // that don't set an explicit background were falling back
                // to the system's dark-mode default (near-black) whenever
                // the device was in Dark Mode, while only Home (which sets
                // its own cream background explicitly) looked right.
                // Forcing light appearance app-wide is the systemic fix;
                // the retrofit of each screen's own background is
                // separate and still needed for true visual consistency.
                .preferredColorScheme(.light)
        }
        .modelContainer(sharedModelContainer)
        .environment(accountState)
        .environment(activeCookbookState)
        .environment(cookingSessionState)
    }
}
