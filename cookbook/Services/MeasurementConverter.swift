//
//  MeasurementConverter.swift
//  cookbook
//
//  Pure logic, no SwiftUI, matching RecipeSearch.swift's own "testable
//  without SwiftUI" convention. Volume and weight are kept as two
//  separate unit systems, never cross-converted — going from one to the
//  other needs an ingredient's density, which this doesn't (and
//  shouldn't try to) know.
//

import Foundation

enum ConversionCategory: String, CaseIterable, Identifiable {
    case volume = "Volume"
    case weight = "Weight"

    var id: String { rawValue }

    var units: [MeasurementUnit] {
        switch self {
        case .volume: return MeasurementUnit.volumeUnits
        case .weight: return MeasurementUnit.weightUnits
        }
    }
}

struct MeasurementUnit: Identifiable, Hashable {
    var name: String
    var abbreviation: String
    /// How many of this unit's base (milliliters for volume, grams for
    /// weight) equal exactly one of this unit.
    var unitsPerBase: Double

    var id: String { name }

    static let volumeUnits: [MeasurementUnit] = [
        MeasurementUnit(name: "Teaspoon", abbreviation: "tsp", unitsPerBase: 4.92892),
        MeasurementUnit(name: "Tablespoon", abbreviation: "tbsp", unitsPerBase: 14.7868),
        MeasurementUnit(name: "Fluid Ounce", abbreviation: "fl oz", unitsPerBase: 29.5735),
        MeasurementUnit(name: "Cup", abbreviation: "cup", unitsPerBase: 236.588),
        MeasurementUnit(name: "Pint", abbreviation: "pt", unitsPerBase: 473.176),
        MeasurementUnit(name: "Quart", abbreviation: "qt", unitsPerBase: 946.353),
        MeasurementUnit(name: "Gallon", abbreviation: "gal", unitsPerBase: 3785.41),
        MeasurementUnit(name: "Milliliter", abbreviation: "ml", unitsPerBase: 1),
        MeasurementUnit(name: "Liter", abbreviation: "L", unitsPerBase: 1000),
    ]

    static let weightUnits: [MeasurementUnit] = [
        MeasurementUnit(name: "Ounce", abbreviation: "oz", unitsPerBase: 28.3495),
        MeasurementUnit(name: "Pound", abbreviation: "lb", unitsPerBase: 453.592),
        MeasurementUnit(name: "Gram", abbreviation: "g", unitsPerBase: 1),
        MeasurementUnit(name: "Kilogram", abbreviation: "kg", unitsPerBase: 1000),
    ]
}

enum MeasurementConverter {
    /// Converts `value` from `fromUnit` to `toUnit` — both must come from
    /// the same category's unit list (volume units only ever convert to
    /// other volume units, same for weight); callers can't mix them since
    /// ConversionCategory.units is the only place either list comes from.
    static func convert(_ value: Double, from fromUnit: MeasurementUnit, to toUnit: MeasurementUnit) -> Double {
        let baseValue = value * fromUnit.unitsPerBase
        return baseValue / toUnit.unitsPerBase
    }
}
