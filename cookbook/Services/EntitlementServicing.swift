//
//  EntitlementServicing.swift
//  cookbook
//
//  Read/query side of entitlements/{uid}. Granting promo credits stays in
//  EntitlementGranting (Milestone 2A); StoreKit purchase flow and applying
//  a purchase to this same document is Milestone 2D. createGroup's credit
//  consumption (GroupsServicing) reads/writes this document directly in
//  its own transaction rather than going through this protocol, since that
//  write has to be atomic with the group/membership writes.
//

import Foundation

protocol EntitlementServicing {
    func fetchEntitlement(userID: String) async throws -> Entitlement?
    func hasFamilyUser(userID: String) async throws -> Bool
    func availableCreationCredits(userID: String) async throws -> Int
}

extension EntitlementServicing {
    func hasFamilyUser(userID: String) async throws -> Bool {
        try await fetchEntitlement(userID: userID)?.hasFamilyUser ?? false
    }

    func availableCreationCredits(userID: String) async throws -> Int {
        try await fetchEntitlement(userID: userID)?.creationCredits ?? 0
    }
}
