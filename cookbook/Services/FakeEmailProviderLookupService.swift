//
//  FakeEmailProviderLookupService.swift
//  cookbook
//

import Foundation

final class FakeEmailProviderLookupService: EmailProviderLookupServicing {
    var statusByEmail: [String: EmailAccountStatus] = [:]
    private(set) var lookedUpEmails: [String] = []

    func resolveProviders(email: String) async throws -> EmailAccountStatus {
        lookedUpEmails.append(email)
        return statusByEmail[email] ?? .notFound
    }
}
