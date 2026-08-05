//
//  IngredientSection.swift
//  cookbook
//

import Foundation
import SwiftData

@Model
final class IngredientSection {
    var id: UUID
    var heading: String?
    var sortOrder: Int

    @Relationship(deleteRule: .cascade, inverse: nil)
    var ingredients: [Ingredient]

    init(heading: String? = nil, sortOrder: Int = 0) {
        self.id = UUID()
        self.heading = heading
        self.sortOrder = sortOrder
        self.ingredients = []
    }
}

@Model
final class Ingredient {
    var id: UUID

    /// The raw author-entered string ("1 1/2 cups flour, sifted") — preserved
    /// verbatim per REC-004 even once/if normalized parsing exists.
    var displayText: String

    /// Best-effort parsed quantity for future scaling/search. Optional
    /// because not every ingredient line is scalable ("salt, to taste").
    var quantityValue: Double?
    var unit: String?
    var name: String
    var preparationNote: String?
    var isOptional: Bool
    var sortOrder: Int

    init(
        displayText: String,
        name: String,
        quantityValue: Double? = nil,
        unit: String? = nil,
        preparationNote: String? = nil,
        isOptional: Bool = false,
        sortOrder: Int = 0
    ) {
        self.id = UUID()
        self.displayText = displayText
        self.quantityValue = quantityValue
        self.unit = unit
        self.name = name
        self.preparationNote = preparationNote
        self.isOptional = isOptional
        self.sortOrder = sortOrder
    }
}
