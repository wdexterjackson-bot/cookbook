//
//  TagCatalog.swift
//  cookbook
//
//  Suggested default tags offered in the tag picker — mirrors
//  RecipeSectionCatalog's shape. Recipe.tags is free-form; this is just a
//  starting-point suggestion list, not an enum constraint.
//

import Foundation

enum TagCatalog {
    static let suggestedTags: [String] = [
        "Quick",
        "Freezer-Friendly",
        "Kid-Friendly",
        "One-Pot",
        "Make-Ahead",
        "Leftovers",
        "Spicy",
        "Comfort Food",
        "Holiday",
        "Party",
        "Healthy",
        "Budget-Friendly",
    ]
}
