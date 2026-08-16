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
//  Matching is regex-based specifically so the quantity can be found even
//  when it's run directly into the unit with no space ("280g", "5g") —
//  previously this split on whitespace first and tried to parse the whole
//  first token as a number, so "280g" (not a valid Double) failed to
//  parse at all and the entire line fell back to being read as an
//  unparsed name (2026-08-15 feedback: Discover-tab imports in grams were
//  silently dropping their quantity). Anchoring the regex at the start and
//  taking only the numeric run it matches means whatever immediately
//  follows — a space or not — is left for the caller to read as unit/name.
//

import Foundation

enum LeadingQuantityToken {
    private static let mixedNumberPattern = try! NSRegularExpression(
        pattern: #"^(\d+(?:\.\d+)?)\s+(\d+(?:\.\d+)?)/(\d+(?:\.\d+)?)"#
    )
    private static let fractionPattern = try! NSRegularExpression(
        pattern: #"^(\d+(?:\.\d+)?)/(\d+(?:\.\d+)?)"#
    )
    // The trailing `(?!/)` matters: without it, a malformed fraction like
    // "1/0 cups" (caught and rejected by the fractionPattern branch above,
    // since a zero denominator can't be evaluated) would otherwise fall
    // through and get misread here as the bare decimal "1", silently
    // dropping the "/0" instead of failing the whole quantity as it
    // should.
    private static let decimalPattern = try! NSRegularExpression(pattern: #"^\d+(?:\.\d+)?(?!/)"#)

    /// Returns the parsed decimal value and the exact substring that
    /// represents it, or nil if `text` doesn't start with a recognizable
    /// quantity. `matchedText` is what a caller should strip/replace —
    /// never more than the leading whole+fraction pair, so trailing
    /// content (units, prep notes) is never touched here.
    static func parse(from text: String) -> (value: Double, matchedText: String)? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        // Mixed number: "1 1/2 cups flour" / "1 1/2g sugar".
        if let match = firstMatch(mixedNumberPattern, in: trimmed),
           let whole = Double(match.groups[0]),
           let numerator = Double(match.groups[1]),
           let denominator = Double(match.groups[2]), denominator != 0 {
            return (whole + numerator / denominator, match.text)
        }
        // Plain fraction: "1/2 cups flour" / "1/2g sugar".
        if let match = firstMatch(fractionPattern, in: trimmed),
           let numerator = Double(match.groups[0]),
           let denominator = Double(match.groups[1]), denominator != 0 {
            return (numerator / denominator, match.text)
        }
        // Plain decimal or whole number: "1.5 cups flour", "2 cups flour",
        // and — the actual fix — "280g flour", "5g salt" with no space at
        // all before the unit.
        if let match = firstMatch(decimalPattern, in: trimmed), let value = Double(match.text) {
            return (value, match.text)
        }
        return nil
    }

    private static func firstMatch(_ regex: NSRegularExpression, in text: String) -> (text: String, groups: [String])? {
        let fullRange = NSRange(text.startIndex..., in: text)
        guard let result = regex.firstMatch(in: text, range: fullRange),
              let matchedRange = Range(result.range, in: text)
        else { return nil }
        let groups = (1..<result.numberOfRanges).compactMap { index -> String? in
            guard let groupRange = Range(result.range(at: index), in: text) else { return nil }
            return String(text[groupRange])
        }
        return (String(text[matchedRange]), groups)
    }
}
