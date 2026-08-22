//
//  FriendlyNameDirectoryTests.swift
//  cookbookTests
//

import Foundation
import Testing
@testable import cookbook

struct FriendlyNameDirectoryTests {

    @Test func labelFallsBackToAShortMemberLabelBeforeLoading() {
        let directory = FriendlyNameDirectory(service: InMemoryPublicProfileService())

        #expect(directory.label(for: "abcdefLZHmH3") == "Member LZHmH3")
    }

    @Test func labelReturnsTheFriendlyNameOnceLoaded() async {
        let service = InMemoryPublicProfileService()
        try? await service.setDisplayName("Dexter Jackson", userID: "alice-uid")
        let directory = FriendlyNameDirectory(service: service)

        await directory.load(userIDs: ["alice-uid"])

        #expect(directory.label(for: "alice-uid") == "Dexter Jackson")
    }

    @Test func aUserIDWithNoProfileKeepsTheFallbackLabel() async {
        let service = InMemoryPublicProfileService()
        let directory = FriendlyNameDirectory(service: service)

        await directory.load(userIDs: ["no-profile-uid123456"])

        #expect(directory.label(for: "no-profile-uid123456") == "Member 123456")
    }
}
