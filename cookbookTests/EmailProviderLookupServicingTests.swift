//
//  EmailProviderLookupServicingTests.swift
//  cookbookTests
//

import Foundation
import Testing
@testable import cookbook

struct EmailProviderLookupServicingTests {

    @Test func returnsNotFoundForAnUnknownEmail() async throws {
        let service = FakeEmailProviderLookupService()

        let status = try await service.resolveProviders(email: "nobody@example.com")

        #expect(status == .notFound)
        #expect(service.lookedUpEmails == ["nobody@example.com"])
    }

    @Test func returnsTheStubbedProvidersForAKnownEmail() async throws {
        let service = FakeEmailProviderLookupService()
        service.statusByEmail["alice@example.com"] = .exists(providers: [.google])

        let status = try await service.resolveProviders(email: "alice@example.com")

        #expect(status == .exists(providers: [.google]))
    }

    @Test func mapsFirebaseProviderIDsToKnownCases() {
        #expect(AuthProviderKind(firebaseProviderID: "password") == .password)
        #expect(AuthProviderKind(firebaseProviderID: "apple.com") == .apple)
        #expect(AuthProviderKind(firebaseProviderID: "google.com") == .google)
        #expect(AuthProviderKind(firebaseProviderID: "phone") == nil)
    }
}
