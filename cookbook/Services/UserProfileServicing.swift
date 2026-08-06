//
//  UserProfileServicing.swift
//  cookbook
//
//  Location has no home elsewhere in the app — Full Name lives on Firebase
//  Auth's own displayName (AccountState.currentUserDisplayName), but Auth
//  doesn't support arbitrary custom profile fields from the client SDK.
//  This is a small, user-owned Firestore doc instead (userProfiles/{uid}),
//  written directly by the client — no Cloud Function needed, unlike the
//  group-deletion work, since nothing here is security-sensitive.
//

import Foundation

struct UserLocation: Codable, Equatable {
    var city: String
    var isUS: Bool
    /// Two-letter state abbreviation, e.g. "TN" — set when isUS.
    var stateCode: String?
    /// Full country name, e.g. "Canada" — set when !isUS.
    var country: String?

    /// "City, ST" or "City, Country" — the exact format recipe lineage and
    /// Settings display both use.
    var formatted: String {
        if isUS, let stateCode, !stateCode.isEmpty {
            return "\(city), \(stateCode)"
        }
        if let country, !country.isEmpty {
            return "\(city), \(country)"
        }
        return city
    }
}

enum USState {
    /// (name, two-letter abbreviation) — shared by the Settings location
    /// picker and the recipe-creation author prompt, so both stay in sync.
    static let all: [(name: String, code: String)] = [
        ("Alabama", "AL"), ("Alaska", "AK"), ("Arizona", "AZ"), ("Arkansas", "AR"),
        ("California", "CA"), ("Colorado", "CO"), ("Connecticut", "CT"), ("Delaware", "DE"),
        ("District of Columbia", "DC"), ("Florida", "FL"), ("Georgia", "GA"), ("Hawaii", "HI"),
        ("Idaho", "ID"), ("Illinois", "IL"), ("Indiana", "IN"), ("Iowa", "IA"),
        ("Kansas", "KS"), ("Kentucky", "KY"), ("Louisiana", "LA"), ("Maine", "ME"),
        ("Maryland", "MD"), ("Massachusetts", "MA"), ("Michigan", "MI"), ("Minnesota", "MN"),
        ("Mississippi", "MS"), ("Missouri", "MO"), ("Montana", "MT"), ("Nebraska", "NE"),
        ("Nevada", "NV"), ("New Hampshire", "NH"), ("New Jersey", "NJ"), ("New Mexico", "NM"),
        ("New York", "NY"), ("North Carolina", "NC"), ("North Dakota", "ND"), ("Ohio", "OH"),
        ("Oklahoma", "OK"), ("Oregon", "OR"), ("Pennsylvania", "PA"), ("Rhode Island", "RI"),
        ("South Carolina", "SC"), ("South Dakota", "SD"), ("Tennessee", "TN"), ("Texas", "TX"),
        ("Utah", "UT"), ("Vermont", "VT"), ("Virginia", "VA"), ("Washington", "WA"),
        ("West Virginia", "WV"), ("Wisconsin", "WI"), ("Wyoming", "WY"),
    ]
}

protocol UserProfileServicing {
    func fetchLocation(userID: String) async throws -> UserLocation?
    func setLocation(_ location: UserLocation, userID: String) async throws
    /// Account deletion cleanup — best-effort by design, same as
    /// EntitlementServicing.deleteEntitlement.
    func deleteProfile(userID: String) async throws
}
