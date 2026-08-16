//
//  IngredientLineParserTests.swift
//  cookbookTests
//

import Foundation
import Testing
@testable import cookbook

struct IngredientLineParserTests {
    private let knownUnits = CreateEditRecipeView.commonUnits

    // MARK: - No space between quantity and unit (2026-08-15 feedback)

    @Test func parsesAGramAmountWithNoSpaceBeforeTheUnit() {
        let parsed = IngredientLineParser.parse("280g flour", knownUnits: knownUnits)
        #expect(parsed.quantity == 280)
        #expect(parsed.unit == "g")
        #expect(parsed.name == "flour")
    }

    @Test func parsesASingleDigitGramAmountWithNoSpaceBeforeTheUnit() {
        let parsed = IngredientLineParser.parse("5g salt", knownUnits: knownUnits)
        #expect(parsed.quantity == 5)
        #expect(parsed.unit == "g")
        #expect(parsed.name == "salt")
    }

    // MARK: - Unit aliases (2026-08-15 feedback: "tblsp"/"pkg"/"pkge" weren't recognized)

    @Test func mapsTblspToTbsp() {
        let parsed = IngredientLineParser.parse("2 tblsp olive oil", knownUnits: knownUnits)
        #expect(parsed.unit == "tbsp")
        #expect(parsed.name == "olive oil")
    }

    @Test func mapsPkgToPackage() {
        let parsed = IngredientLineParser.parse("1 pkg cream cheese", knownUnits: knownUnits)
        #expect(parsed.unit == "package")
        #expect(parsed.name == "cream cheese")
    }

    @Test func mapsPkgeToPackage() {
        let parsed = IngredientLineParser.parse("1 pkge yeast", knownUnits: knownUnits)
        #expect(parsed.unit == "package")
        #expect(parsed.name == "yeast")
    }
}
