//
//  AuthServicing.swift
//  cookbook
//
//  The seam for authentication: FirebaseAuthService is the real adapter,
//  FakeAuthService backs tests/previews. Nothing outside this file and its
//  adapter should import FirebaseAuth directly.
//

import Foundation

struct AuthResult: Equatable {
    let userID: String
    /// True only when this call created a brand-new account (sign-up, or a
    /// federated credential's first use) — distinguishes account creation
    /// from an ordinary sign-in, since only creation grants promo credits.
    let isNewAccount: Bool
}

enum AuthServiceError: Error, Equatable {
    case notSignedIn
    case invalidCredential
    /// Firebase requires a recent sign-in for security-sensitive actions
    /// like account deletion. Callers should ask the user to sign out and
    /// back in, then retry, rather than the app attempting inline
    /// re-authentication.
    case requiresRecentLogin
}

protocol AuthServicing {
    var currentUserID: String? { get }
    /// Used to look up invitations addressed to this user (Invitation's
    /// `inviteeIdentifier` is an email, not a UID, since an invite can be
    /// sent before the invitee has ever signed up).
    var currentUserEmail: String? { get }

    func signInWithEmail(email: String, password: String) async throws -> AuthResult
    func signUpWithEmail(email: String, password: String) async throws -> AuthResult
    func signInWithApple(idToken: String, rawNonce: String) async throws -> AuthResult
    func signInWithGoogle(idToken: String, accessToken: String) async throws -> AuthResult
    func signOut() throws
    func deleteAccount() async throws
}
