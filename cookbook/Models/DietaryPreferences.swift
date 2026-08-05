//
//  DietaryPreferences.swift
//  cookbook
//
//  Device-level preference (like LocalOwner), not a SwiftData table — one
//  record, no query/relationship needs.
//

import Foundation

/// Raw values match the exact strings Spoonacular's `diet` parameter
/// accepts (confirmed live: vegan, vegetarian, pescetarian, "gluten free").
enum DietPreference: String, Codable, CaseIterable, Identifiable {
    case none
    case vegan
    case vegetarian
    case pescetarian
    case glutenFree = "gluten free"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: return "No Preference"
        case .vegan: return "Vegan"
        case .vegetarian: return "Vegetarian"
        case .pescetarian: return "Pescatarian"
        case .glutenFree: return "Gluten Free"
        }
    }
}

/// Raw values match Spoonacular's `intolerances` parameter's stable enum.
enum AllergenPreference: String, Codable, CaseIterable, Identifiable {
    case dairy
    case egg
    case gluten
    case grain
    case peanut
    case seafood
    case sesame
    case shellfish
    case soy
    case sulfite
    case treeNut = "tree nut"
    case wheat

    var id: String { rawValue }

    var label: String {
        switch self {
        case .treeNut: return "Tree Nut"
        default: return rawValue.capitalized
        }
    }
}

struct DietaryPreferences: Codable, Equatable {
    var defaultDiet: DietPreference
    var excludedAllergens: Set<AllergenPreference>

    static let `default` = DietaryPreferences(defaultDiet: .none, excludedAllergens: [])
}

enum DietaryPreferencesStore {
    private static let defaultsKey = "com.vibeapp.cookbook.dietaryPreferences"

    /// Takes an explicit UserDefaults (defaulting to .standard for real
    /// use) rather than always touching the shared store directly — tests
    /// pass an isolated suite so parallel test runs can't race each other
    /// through global UserDefaults.standard state.
    static func current(in defaults: UserDefaults = .standard) -> DietaryPreferences {
        guard let data = defaults.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode(DietaryPreferences.self, from: data)
        else {
            return .default
        }
        return decoded
    }

    static func setCurrent(_ preferences: DietaryPreferences, in defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(data, forKey: defaultsKey)
    }
}
