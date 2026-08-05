//
//  Entitlement.swift
//  cookbook
//

import Foundation

struct Entitlement: Codable, Equatable {
    var userID: String
    var creationCredits: Int
    var hasFamilyUser: Bool
    var grantedPromoCredits: Bool
    var createdAt: Date
}
