//
//  InMemoryEntitlementService.swift
//  cookbook
//

import Foundation

final class InMemoryEntitlementService: EntitlementServicing {
    var entitlementsByUserID: [String: Entitlement] = [:]

    func fetchEntitlement(userID: String) async throws -> Entitlement? {
        entitlementsByUserID[userID]
    }
}
