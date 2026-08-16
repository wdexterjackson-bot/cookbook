//
//  CookbookSectionIconCatalog.swift
//  cookbook
//
//  Chapter icons offered in CookbookConfigurationView, bundled as image
//  assets under Assets.xcassets/SectionIcons (imported from the
//  "Cookbook Sections Icons" manifest — 38 categories, each with a
//  full-color and a black variant sharing the same base filename).
//  CookbookSection.iconAssetName stores assetName directly, matching
//  CookbookCoverStyleCatalog's own pattern for cover styles.
//

import Foundation

struct CookbookSectionIcon: Identifiable, Equatable {
    var assetName: String
    var displayName: String
    var isFullColor: Bool

    var id: String { assetName }
}

enum CookbookSectionIconCatalog {
    /// One entry per manifest category. "Glutten Free" in the source
    /// manifest/filenames is a typo carried over from the original asset
    /// export — corrected here for the user-facing displayName only; the
    /// underlying asset filenames (an internal identifier, never shown)
    /// are left exactly as exported.
    private static let categories: [(displayName: String, baseFilename: String)] = [
        ("Appetizers", "01-appetizers"),
        ("Bakery", "33-bakery"),
        ("Bakery (Breads & Rolls)", "09-bakery-breads-and-rolls"),
        ("Beverage", "13-beverage"),
        ("Breakfast", "10-breakfast"),
        ("Brunch", "20-brunch"),
        ("Cakes", "34-cakes"),
        ("Cakes, Pies, & Pastries", "11-cakes-pies-and-pastries"),
        ("Casseroles", "32-casseroles"),
        ("Cookies", "35-cookies"),
        ("Desserts", "12-desserts"),
        ("Dinner", "19-dinner"),
        ("Fish", "23-fish"),
        ("Gluten Free", "27-glutten-free"),
        ("Jams and Preserves", "37-jams-and-preserves"),
        ("Lunch", "18-lunch"),
        ("Martinis", "38-martinis"),
        ("Meals & Main Courses", "03-meals-and-main-courses"),
        ("Meat", "15-meat"),
        ("Meat & Meal Prep", "05-meat-and-meal-prep"),
        ("Meats, Poultry, Fish", "04-meats-poultry-fish"),
        ("On the Grill", "14-on-the-grill"),
        ("Pasta", "31-pasta"),
        ("Poultry", "16-poultry"),
        ("Salads", "21-salads"),
        ("Salsas", "29-salsas"),
        ("Sauces", "28-sauces"),
        ("Sauces, Dips, Relishes, & Pickles", "02-sauces-dips-relishes-and-pickles"),
        ("Seafood & Fish", "06-seafood-and-fish"),
        ("Seasonings & Meal Prep", "17-seasonings-and-meal-prep"),
        ("Side Dishes", "30-side-dishes"),
        ("Snacks", "36-snacks"),
        ("Soups", "22-soups"),
        ("Soups, Salads, & Sandwiches", "07-soups-salads-and-sandwiches"),
        ("Vegan", "25-vegan"),
        ("Vegetable & Side Dishes", "08-vegetable-and-side-dishes"),
        ("Vegetables", "24-vegetables"),
        ("Vegetarian", "26-vegetarian"),
    ]

    /// Full-color entries first (alphabetical by displayName), then every
    /// black entry (same alphabetical order) — the exact picker ordering
    /// requested: "full color versions at the top, followed by the black
    /// at the end."
    static let allIcons: [CookbookSectionIcon] =
        categories.map { CookbookSectionIcon(assetName: "section-fc-\($0.baseFilename)", displayName: $0.displayName, isFullColor: true) }
        + categories.map { CookbookSectionIcon(assetName: "section-bw-\($0.baseFilename)", displayName: $0.displayName, isFullColor: false) }

    static func icon(named assetName: String?) -> CookbookSectionIcon? {
        guard let assetName else { return nil }
        return allIcons.first { $0.assetName == assetName }
    }

    /// The full-color icon whose category exactly matches a chapter title
    /// (case-insensitive) — used to auto-assign a default the moment a
    /// chapter is added. RecipeSectionCatalog's chapter list is itself
    /// sourced from these same category names, so every catalog-picked
    /// chapter always has exactly one match; a custom-named chapter
    /// typically has none, which is fine — no default icon isn't an error,
    /// just nothing shown until the user picks one manually.
    static func defaultIcon(forChapterTitled title: String) -> CookbookSectionIcon? {
        allIcons.first { $0.isFullColor && $0.displayName.caseInsensitiveCompare(title) == .orderedSame }
    }
}
