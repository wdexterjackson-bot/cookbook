//
//  LeadingQuantityToken.swift
//  cookbook
//
//  Recognizes a quantity expression at the very start of an ingredient's
//  displayText — plain decimals ("1.5"), plain fractions ("1/2"), and
//  mixed numbers ("1 1/2") — so RecipeQuantityStandardizer can recover a
//  quantityValue that was never captured (typing "1/2" into the old
//  decimal-only amount field silently failed to parse) and safely rewrite
//  just that leading portion of displayText, leaving everything after it
//  (unit, name, any trailing author notes) untouched.
//

import Foundation

enum LeadingQuantityToken {
    /// Returns the parsed decimal value and the exact substring that
    /// represents it, or nil if `text` doesn't start with a recognizable
    /// quantity. `matchedText` is what a caller should strip/replace —
    /// never more than the leading whole+fraction pair, so trailing
    /// content (units, prep notes) is never touched here.
    static func parse(from text: String) -> (value: Double, matchedText: String)? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let tokens = trimmed.split(separator: " ", omittingEmptySubsequences: true)
        guard let first = tokens.first else { return nil }

        // Mixed number: "1 1/2 cups flour" — a whole-number token
        // immediately followed by a fraction token.
        if tokens.count >= 2, let whole = Int(first), whole >= 0,
           let fractionValue = parseFraction(tokens[1]) {
            return (Double(whole) + fractionValue, "\(first) \(tokens[1])")
        }
        // Plain fraction: "1/2 cups flour"
        if let fractionValue = parseFraction(first) {
            return (fractionValue, String(first))
        }
        // Plain decimal or whole number: "1.5 cups flour", "2 cups flour"
        if let value = Double(first), value >= 0 {
            return (value, String(first))
        }
        return nil
    }

    private static func parseFraction(_ token: Substring) -> Double? {
        let parts = token.split(separator: "/")
        guard parts.count == 2,
              let numerator = Double(parts[0]),
              let denominator = Double(parts[1]),
              denominator != 0
        else { return nil }
        return numerator / denominator
    }
}
