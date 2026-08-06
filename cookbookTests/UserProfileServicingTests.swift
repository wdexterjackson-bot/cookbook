//
//  UserProfileServicingTests.swift
//  cookbookTests
//

import Foundation
import Testing
@testable import cookbook

struct UserProfileServicingTests {

    @Test func formatsAUSLocationAsCityCommaState() {
        let location = UserLocation(city: "Memphis", isUS: true, stateCode: "TN", country: nil)

        #expect(location.formatted == "Memphis, TN")
    }

    @Test func formatsAnInternationalLocationAsCityCommaCountry() {
        let location = UserLocation(city: "Toronto", isUS: false, stateCode: nil, country: "Canada")

        #expect(location.formatted == "Toronto, Canada")
    }

    @Test func formatsJustTheCityWhenNoStateOrCountryIsSet() {
        let location = UserLocation(city: "Memphis", isUS: true, stateCode: nil, country: nil)

        #expect(location.formatted == "Memphis")
    }

    @Test func inMemoryServiceStoresAndDeletesLocationsPerUser() async throws {
        let service = InMemoryUserProfileService()
        let location = UserLocation(city: "Memphis", isUS: true, stateCode: "TN", country: nil)

        try await service.setLocation(location, userID: "alice")
        let fetched = try await service.fetchLocation(userID: "alice")
        #expect(fetched == location)

        try await service.deleteProfile(userID: "alice")
        let afterDelete = try await service.fetchLocation(userID: "alice")
        #expect(afterDelete == nil)
    }
}
