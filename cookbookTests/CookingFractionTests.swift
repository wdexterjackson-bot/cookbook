//
//  CookingFractionTests.swift
//  cookbookTests
//

import Foundation
import Testing
@testable import cookbook

struct CookingFractionTests {

    @Test func nearestSnapsToClosestFraction() {
        #expect(CookingFraction.nearest(to: 0.0) == .none)
        #expect(CookingFraction.nearest(to: 0.13) == .oneEighth)
        #expect(CookingFraction.nearest(to: 0.24) == .oneQuarter)
        #expect(CookingFraction.nearest(to: 0.34) == .oneThird)
        #expect(CookingFraction.nearest(to: 0.5) == .oneHalf)
        #expect(CookingFraction.nearest(to: 0.66) == .twoThirds)
        #expect(CookingFraction.nearest(to: 0.9) == .sevenEighths)
    }

    @Test func displayTextMatchesCommonCookingNotation() {
        #expect(CookingFraction.oneEighth.displayText == "1/8")
        #expect(CookingFraction.oneThird.displayText == "1/3")
        #expect(CookingFraction.oneHalf.displayText == "1/2")
        #expect(CookingFraction.twoThirds.displayText == "2/3")
        #expect(CookingFraction.none.displayText == "")
    }

    @Test func wheelQuantityDisplayTextCombinesWholeAndFraction() {
        #expect(WheelQuantity(whole: 0, fraction: .none).displayText == "")
        #expect(WheelQuantity(whole: 0, fraction: .oneHalf).displayText == "1/2")
        #expect(WheelQuantity(whole: 2, fraction: .none).displayText == "2")
        #expect(WheelQuantity(whole: 1, fraction: .oneHalf).displayText == "1 1/2")
    }

    @Test func wheelQuantityValueIsNilWhenZero() {
        #expect(WheelQuantity.zero.quantityValue == nil)
        #expect(WheelQuantity(whole: 0, fraction: .none).quantityValue == nil)
        #expect(WheelQuantity(whole: 1, fraction: .none).quantityValue == 1.0)
    }

    @Test func nearestToValueRoundTripsWholeNumbers() {
        let snapped = WheelQuantity.nearest(to: 3.0)
        #expect(snapped.whole == 3)
        #expect(snapped.fraction == .none)
    }

    @Test func nearestToValueSnapsFractionalRemainder() {
        let snapped = WheelQuantity.nearest(to: 1.48)
        #expect(snapped.whole == 1)
        #expect(snapped.fraction == .oneHalf)
    }

    @Test func nearestToNilOrZeroReturnsZero() {
        #expect(WheelQuantity.nearest(to: nil) == .zero)
        #expect(WheelQuantity.nearest(to: 0) == .zero)
        #expect(WheelQuantity.nearest(to: -1) == .zero)
    }
}
