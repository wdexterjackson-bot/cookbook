//
//  FirebaseEmailProviderLookupService.swift
//  cookbook
//

import FirebaseFunctions
import Foundation

final class FirebaseEmailProviderLookupService: EmailProviderLookupServicing {
    private let functions = Functions.functions()

    func resolveProviders(email: String) async throws -> EmailAccountStatus {
        let callable = functions.httpsCallable("resolveSignInProviders")
        let result = try await callable.call(["email": email])

        guard let data = result.data as? [String: Any] else {
            return .notFound
        }

        let exists = data["exists"] as? Bool ?? false
        guard exists else { return .notFound }

        let providerIDs = data["providers"] as? [String] ?? []
        let providers = providerIDs.compactMap(AuthProviderKind.init(firebaseProviderID:))
        return .exists(providers: providers)
    }
}
