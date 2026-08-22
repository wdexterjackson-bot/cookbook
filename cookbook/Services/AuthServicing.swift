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

extension AuthServiceError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "You're not signed in."
        case .invalidCredential: return "That email or password isn't right."
        case .requiresRecentLogin: return "For your security, sign out and back in before trying this again."
        }
    }
}

protocol AuthServicing {
    var currentUserID: String? { get }
    /// Used to look up invitations addressed to this user (Invitation's
    /// `inviteeIdentifier` is an email, not a UID, since an invite can be
    /// sent before the invitee has ever signed up).
    var currentUserEmail: String? { get }
    /// First + last name, entered at sign-up (or pulled from an Apple/Google
    /// credential on first federated sign-in) — powers the Home greeting
    /// and, later, recipe-lineage attribution. Nil until set.
    var currentUserDisplayName: String? { get }

    func signInWithEmail(email: String, password: String) async throws -> AuthResult
    func signUpWithEmail(email: String, password: String, displayName: String) async throws -> AuthResult
    /// Sends Firebase's own hosted "reset your password" email — the user
    /// picks a brand-new password via the link, nothing about their old
    /// one is ever read back to anyone (Firebase's password hashing is
    /// one-way; there is no "email me my current password" capability).
    /// Succeeds even for an email with no account, matching
    /// EmailProviderLookupServicing's same anti-enumeration stance — never
    /// use this call's success/failure to tell a user whether an account
    /// exists.
    func sendPasswordReset(email: String) async throws
    func signInWithApple(idToken: String, rawNonce: String) async throws -> AuthResult
    func signInWithGoogle(idToken: String, accessToken: String) async throws -> AuthResult
    /// Apple TV phone-pairing sign-in: the TV exchanges a short-lived,
    /// single-use token minted by the confirmPairingCode/checkPairingStatus
    /// Cloud Functions (functions/tvPairing.js) for a real session, without
    /// ever typing credentials via the remote. Always targets one specific,
    /// already-existing account — never creates one.
    func signInWithCustomToken(_ token: String) async throws -> AuthResult
    func updateDisplayName(_ displayName: String) async throws
    func signOut() throws
    func deleteAccount() async throws
}
