//
//  SignInErrorMessaging.swift
//  cookbook
//
//  Pure, testable classification/formatting logic for SignInView's error
//  messages — kept out of the view body so the duplicate-account /
//  wrong-provider messaging can be unit tested without SwiftUI or a real
//  FirebaseAuth error.
//
//  Modern FirebaseAuth (post email-enumeration-protection rollout, all
//  projects created after 2023-09-15 including this one) deliberately
//  collapses "wrong password" and "no such user" into a single generic
//  .invalidCredential on sign-in, specifically so the client can't tell
//  them apart on its own — that's exactly the gap EmailProviderLookupServicing
//  (a server-side, rate-limited lookup) fills, reactively, after this
//  ambiguous failure already happened.
//

import FirebaseAuth
import Foundation

enum SignInAttemptContext {
    case signUp
    case signIn
}

/// What SignInView should do next after catching an auth error: show a
/// message immediately, or run an EmailProviderLookupServicing lookup
/// (using the given email) before it can show a fully-informed message.
enum SignInErrorClassification: Equatable {
    case immediateMessage(String)
    case needsProviderLookup(email: String, context: SignInAttemptContext)
}

enum SignInErrorMessaging {
    static func classify(_ error: Error, attemptedEmail: String, context: SignInAttemptContext) -> SignInErrorClassification {
        let nsError = error as NSError
        guard nsError.domain == AuthErrors.domain, let code = AuthErrorCode(rawValue: nsError.code) else {
            return .immediateMessage(error.localizedDescription)
        }

        switch code {
        case .emailAlreadyInUse, .accountExistsWithDifferentCredential, .credentialAlreadyInUse:
            let conflictEmail = (nsError.userInfo[AuthErrors.userInfoEmailKey] as? String) ?? attemptedEmail
            return .needsProviderLookup(email: conflictEmail, context: context)
        case .wrongPassword, .userNotFound, .invalidCredential:
            // Firebase deliberately won't say which of these it is — ask
            // our own server-side lookup instead of guessing.
            return .needsProviderLookup(email: attemptedEmail, context: context)
        default:
            return .immediateMessage(error.localizedDescription)
        }
    }

    /// Once the lookup result is in hand, the final message to show.
    static func message(for status: EmailAccountStatus, context: SignInAttemptContext) -> String {
        switch (status, context) {
        case (.notFound, .signIn):
            return "No account found for this email."
        case (.notFound, .signUp):
            // Shouldn't happen (Firebase already said this email is taken),
            // but fall back to something actionable rather than blank.
            return "That email couldn't be used — it may already be registered. Try signing in instead."
        case (.exists(let providers), .signUp):
            return "An account with this email already exists (created with \(displayList(providers))). Try signing in that way instead."
        case (.exists(let providers), .signIn):
            if providers.contains(.password) {
                return "Incorrect password for this email."
            }
            return "This email is registered with \(displayList(providers)) — sign in that way instead."
        }
    }

    private static func displayList(_ providers: [AuthProviderKind]) -> String {
        let names = providers.map(\.displayName)
        guard !names.isEmpty else { return "a different method" }
        return ListFormatter.localizedString(byJoining: names)
    }
}
