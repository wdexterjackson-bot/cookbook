//
//  QRCodePayloadTests.swift
//  cookbookTests
//

import Foundation
import Testing
@testable import cookbook

struct QRCodePayloadTests {

    @Test func groupPayloadRoundTrips() {
        let payload = QRCodePayload.group(id: "group-1")

        #expect(payload.stringValue == "cookbook:group:group-1")
        #expect(QRCodePayload(stringValue: payload.stringValue) == payload)
    }

    @Test func friendPayloadRoundTrips() {
        let payload = QRCodePayload.friend(id: "user-1")

        #expect(payload.stringValue == "cookbook:friend:user-1")
        #expect(QRCodePayload(stringValue: payload.stringValue) == payload)
    }

    @Test func rejectsAnUnrelatedString() {
        #expect(QRCodePayload(stringValue: "https://example.com") == nil)
    }

    @Test func rejectsAnUnknownKind() {
        #expect(QRCodePayload(stringValue: "cookbook:recipe:recipe-1") == nil)
    }

    @Test func rejectsAnEmptyID() {
        #expect(QRCodePayload(stringValue: "cookbook:group:") == nil)
    }

    @Test func rejectsAMalformedPayloadWithTooFewParts() {
        #expect(QRCodePayload(stringValue: "cookbook:group") == nil)
    }

    @Test func idsContainingColonsSurviveRoundTripping() {
        // Composite IDs elsewhere in this app (e.g. Membership) use "_"
        // as their separator, not ":", but this guards against a ":" ever
        // appearing in an id without silently truncating it.
        let payload = QRCodePayload.friend(id: "weird:id:with:colons")

        #expect(QRCodePayload(stringValue: payload.stringValue) == payload)
    }
}
