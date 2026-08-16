//
//  LeadingQuantityTokenTests.swift
//  cookbookTests
//

import Foundation
import Testing
@testable import cookbook

struct LeadingQuantityTokenTests {

    @Test func parsesPlainDecimal() {
        let parsed = LeadingQuantityToken.parse(from: "1.5 cups flour")
        #expect(parsed?.value == 1.5)
        #expect(parsed?.matchedText == "1.5")
    }

    @Test func parsesPlainFraction() {
        let parsed = LeadingQuantityToken.parse(from: "1/2 tsp salt")
        #expect(parsed?.value == 0.5)
        #expect(parsed?.matchedText == "1/2")
    }

    @Test func parsesMixedNumber() {
        let parsed = LeadingQuantityToken.parse(from: "1 1/2 cups flour")
        #expect(parsed?.value == 1.5)
        #expect(parsed?.matchedText == "1 1/2")
    }

    @Test func parsesMixedNumberWithTrailingAuthorNote() {
        let parsed = LeadingQuantityToken.parse(from: "2 1/3 cups flour, sifted")
        #expect(parsed?.value.isApproximately(2.0 + 1.0 / 3.0) == true)
        #expect(parsed?.matchedText == "2 1/3")
    }

    @Test func parsesWholeNumberOnly() {
        let parsed = LeadingQuantityToken.parse(from: "2 eggs")
        #expect(parsed?.value == 2)
        #expect(parsed?.matchedText == "2")
    }

    @Test func returnsNilWhenNoLeadingQuantity() {
        #expect(LeadingQuantityToken.parse(from: "salt, to taste") == nil)
        #expect(LeadingQuantityToken.parse(from: "") == nil)
    }

    @Test func returnsNilForMalformedFraction() {
        #expect(LeadingQuantityToken.parse(from: "1/0 cups flour") == nil)
    }

    // MARK: - No space between the quantity and unit (2026-08-15 feedback:
    // Discover-tab imports in grams were silently dropping their quantity)

    @Test func parsesWholeNumberRunDirectlyIntoAUnitWithNoSpace() {
        let parsed = LeadingQuantityToken.parse(from: "280g flour")
        #expect(parsed?.value == 280)
        #expect(parsed?.matchedText == "280")
    }

    @Test func parsesASingleDigitRunDirectlyIntoAUnitWithNoSpace() {
        let parsed = LeadingQuantityToken.parse(from: "5g salt")
        #expect(parsed?.value == 5)
        #expect(parsed?.matchedText == "5")
    }

    @Test func parsesAFractionRunDirectlyIntoAUnitWithNoSpace() {
        let parsed = LeadingQuantityToken.parse(from: "1/2g sugar")
        #expect(parsed?.value == 0.5)
        #expect(parsed?.matchedText == "1/2")
    }

    @Test func parsesAMixedNumberRunDirectlyIntoAUnitWithNoSpace() {
        let parsed = LeadingQuantityToken.parse(from: "1 1/2g sugar")
        #expect(parsed?.value == 1.5)
        #expect(parsed?.matchedText == "1 1/2")
    }
}

private extension Double {
    func isApproximately(_ other: Double, tolerance: Double = 0.0001) -> Bool {
        abs(self - other) < tolerance
    }
}
