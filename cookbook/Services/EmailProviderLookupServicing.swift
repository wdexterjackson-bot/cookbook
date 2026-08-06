//
//  EmailProviderLookupServicing.swift
//  cookbook
//
//  The seam for "which sign-in method(s) does this email already use" —
//  deliberately server-side only. Firebase disabled the client-side
//  equivalent (fetchSignInMethodsForEmail) for every project created after
//  2023-09-15 as an anti-enumeration measure; this seam's real adapter
//  calls a Cloud Function (resolveSignInProviders, Admin SDK) instead, and
//  is only ever invoked reactively — after a real sign-up/sign-in attempt
//  already indicated a conflict — never as the user types an email.
//

import Foundation

enum AuthProviderKind: String {
    case password
    case apple
    case google

    /// Maps Firebase's providerId strings (from Auth.User.providerData /
    /// the Admin SDK's UserRecord.providerData) to this enum.
    init?(firebaseProviderID: String) {
        switch firebaseProviderID {
        case "password": self = .password
        case "apple.com": self = .apple
        case "google.com": self = .google
        default: return nil
        }
    }

    var displayName: String {
        switch self {
        case .password: return "Email & Password"
        case .apple: return "Apple"
        case .google: return "Google"
        }
    }
}

enum EmailAccountStatus: Equatable {
    case notFound
    case exists(providers: [AuthProviderKind])
}

protocol EmailProviderLookupServicing {
    func resolveProviders(email: String) async throws -> EmailAccountStatus
}
