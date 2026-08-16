//
//  RecipeSectionCatalog.swift
//  cookbook
//
//  The default chapter names offered when configuring a Cookbook. "Other"
//  in the picker UI means "type a custom name" — it's not a literal entry
//  here.
//
//  Sourced from the same 38-category manifest CookbookSectionIconCatalog
//  uses, kept in sync deliberately — every catalog chapter here has
//  exactly one matching full-color/black icon pair, which is what lets
//  CookbookSectionIconCatalog.defaultIcon(forChapterTitled:) always find
//  a match for a catalog-picked chapter. Alphabetical order, per the
//  picker's own requirement — not the manifest's original numbered order.
//

import Foundation

enum RecipeSectionCatalog {
    static let defaultChapterTitles: [String] = [
        "Appetizers",
        "Bakery",
        "Bakery (Breads & Rolls)",
        "Beverage",
        "Breakfast",
        "Brunch",
        "Cakes",
        "Cakes, Pies, & Pastries",
        "Casseroles",
        "Cookies",
        "Desserts",
        "Dinner",
        "Fish",
        "Gluten Free",
        "Jams and Preserves",
        "Lunch",
        "Martinis",
        "Meals & Main Courses",
        "Meat",
        "Meat & Meal Prep",
        "Meats, Poultry, Fish",
        "On the Grill",
        "Pasta",
        "Poultry",
        "Salads",
        "Salsas",
        "Sauces",
        "Sauces, Dips, Relishes, & Pickles",
        "Seafood & Fish",
        "Seasonings & Meal Prep",
        "Side Dishes",
        "Snacks",
        "Soups",
        "Soups, Salads, & Sandwiches",
        "Vegan",
        "Vegetable & Side Dishes",
        "Vegetables",
        "Vegetarian",
    ]
}
