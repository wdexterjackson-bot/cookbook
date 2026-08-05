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
}

protocol AuthServicing {
    var currentUserID: String? { get }

    func signInWithEmail(email: String, password: String) async throws -> AuthResult
    func signUpWithEmail(email: String, password: String) async throws -> AuthResult
    func signInWithApple(idToken: String, rawNonce: String) async throws -> AuthResult
    func signInWithGoogle(idToken: String, accessToken: String) async throws -> AuthResult
    func signOut() throws
    func deleteAccount() async throws
}
