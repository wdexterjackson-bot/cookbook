//
//  CookingSessionState.swift
//  cookbook
//
//  Home dashboard spec's "Continue Cooking" hero card needs to survive
//  app relaunches — CookingModeView previously tracked step progress as
//  plain @State, which loses it the moment the sheet is dismissed. Same
//  UserDefaults-backed @Observable shape as ActiveCookbookState. Always
//  holds at most one session — starting/advancing a cook overwrites it,
//  matching "the most recent in-progress session," not a history.
//

import Foundation
import Observation

@MainActor
@Observable
final class CookingSessionState {
    private static let defaultsKey = "com.vibeapp.cookbook.cookingSession"

    struct Session: Codable, Equatable {
        var recipeID: UUID
        var ownerID: String
        var recipeTitle: String
        var currentStepIndex: Int
        var totalSteps: Int
        var lastActiveAt: Date
    }

    private(set) var current: Session?

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode(Session.self, from: data) {
            current = decoded
        }
    }

    func update(recipeID: UUID, ownerID: String, recipeTitle: String, currentStepIndex: Int, totalSteps: Int) {
        let session = Session(
            recipeID: recipeID,
            ownerID: ownerID,
            recipeTitle: recipeTitle,
            currentStepIndex: currentStepIndex,
            totalSteps: totalSteps,
            lastActiveAt: .now
        )
        current = session
        if let data = try? JSONEncoder().encode(session) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    func clear() {
        current = nil
        UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
    }
}
