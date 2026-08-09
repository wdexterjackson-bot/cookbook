//
//  CookingFraction.swift
//  cookbook
//
//  Backs the two-wheel amount picker (whole number + fraction) that
//  replaced a free-text decimal field for entering ingredient amounts —
//  eighths (the increments printed on standard US measuring cups/spoons)
//  plus thirds, rather than arbitrary decimal precision nobody actually
//  measures by.
//

import Foundation

enum CookingFraction: CaseIterable, Identifiable, Hashable {
    case none, oneEighth, oneQuarter, oneThird, threeEighths, oneHalf, fiveEighths, twoThirds, threeQuarters, sevenEighths

    var id: Self { self }

    var decimalValue: Double {
        switch self {
        case .none: return 0
        case .oneEighth: return 0.125
        case .oneQuarter: return 0.25
        case .oneThird: return 1.0 / 3.0
        case .threeEighths: return 0.375
        case .oneHalf: return 0.5
        case .fiveEighths: return 0.625
        case .twoThirds: return 2.0 / 3.0
        case .threeQuarters: return 0.75
        case .sevenEighths: return 0.875
        }
    }

    var displayText: String {
        switch self {
        case .none: return ""
        case .oneEighth: return "1/8"
        case .oneQuarter: return "1/4"
        case .oneThird: return "1/3"
        case .threeEighths: return "3/8"
        case .oneHalf: return "1/2"
        case .fiveEighths: return "5/8"
        case .twoThirds: return "2/3"
        case .threeQuarters: return "3/4"
        case .sevenEighths: return "7/8"
        }
    }

    /// The closest fraction to an arbitrary decimal remainder (expected
    /// 0..<1, but tolerant of anything) — used both for snapping a
    /// freshly-typed legacy decimal during migration and for decomposing
    /// an existing Ingredient.quantityValue back into wheel positions when
    /// opening it for editing.
    static func nearest(to remainder: Double) -> CookingFraction {
        allCases.min { abs($0.decimalValue - remainder) < abs($1.decimalValue - remainder) }!
    }
}

/// A whole number + fraction pair — what the two wheels actually produce,
/// and the shared conversion logic between the picker UI and the
/// migration engine that snaps legacy decimal values onto it.
struct WheelQuantity: Equatable {
    var whole: Int
    var fraction: CookingFraction

    static let zero = WheelQuantity(whole: 0, fraction: .none)

    var decimalValue: Double {
        Double(whole) + fraction.decimalValue
    }

    /// nil when representing "no amount" — matches
    /// Ingredient.quantityValue's own "not every line is scalable"
    /// optionality.
    var quantityValue: Double? {
        decimalValue > 0 ? decimalValue : nil
    }

    /// "1 1/2", "3/4", "2", or "" for zero — the wheel-style text shown in
    /// both the compact row summary and a rebuilt Ingredient.displayText.
    var displayText: String {
        switch (whole, fraction) {
        case (0, .none): return ""
        case (0, _): return fraction.displayText
        case (_, .none): return "\(whole)"
        default: return "\(whole) \(fraction.displayText)"
        }
    }

    /// Decomposes an arbitrary decimal into the nearest whole + fraction
    /// combination the wheels can represent. `nil` or non-positive input
    /// both map to zero ("no amount").
    static func nearest(to value: Double?) -> WheelQuantity {
        guard let value, value > 0 else { return .zero }
        let whole = Int(value)
        let remainder = value - Double(whole)
        return WheelQuantity(whole: whole, fraction: .nearest(to: remainder))
    }
}
