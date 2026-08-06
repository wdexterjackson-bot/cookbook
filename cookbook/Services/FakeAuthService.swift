//
//  FakeAuthService.swift
//  cookbook
//
//  In-memory fake for tests/previews — no network, no real Firebase.
//

import Foundation

final class FakeAuthService: AuthServicing {
    private(set) var currentUserID: String?
    private(set) var currentUserEmail: String?
    private var registeredEmails: Set<String> = []

    /// Every distinct (idToken) seen for Apple/Google sign-in is treated as
    /// a distinct account, mirroring Firebase's isNewUser semantics.
    private var seenFederatedTokens: Set<String> = []

    var deleteAccountCallCount = 0
    /// Lets tests simulate Firebase's requiresRecentLogin (or any other)
    /// failure without needing a real stale session.
    var deleteAccountError: Error?

    func signInWithEmail(email: String, password: String) async throws -> AuthResult {
        guard registeredEmails.contains(email) else {
            throw AuthServiceError.invalidCredential
        }
        let userID = "fake-user-\(email)"
        currentUserID = userID
        currentUserEmail = email
        return AuthResult(userID: userID, isNewAccount: false)
    }

    func signUpWithEmail(email: String, password: String) async throws -> AuthResult {
        registeredEmails.insert(email)
        let userID = "fake-user-\(email)"
        currentUserID = userID
        currentUserEmail = email
        return AuthResult(userID: userID, isNewAccount: true)
    }

    func signInWithApple(idToken: String, rawNonce: String) async throws -> AuthResult {
        try signInFederated(token: idToken, provider: "apple")
    }

    func signInWithGoogle(idToken: String, accessToken: String) async throws -> AuthResult {
        try signInFederated(token: idToken, provider: "google")
    }

    private func signInFederated(token: String, provider: String) throws -> AuthResult {
        let userID = "fake-user-\(provider)-\(token)"
        let isNewAccount = !seenFederatedTokens.contains(token)
        seenFederatedTokens.insert(token)
        currentUserID = userID
        currentUserEmail = "\(provider)-\(token)@example.com"
        return AuthResult(userID: userID, isNewAccount: isNewAccount)
    }

    func signOut() throws {
        currentUserID = nil
        currentUserEmail = nil
    }

    func deleteAccount() async throws {
        guard currentUserID != nil else {
            throw AuthServiceError.notSignedIn
        }
        if let deleteAccountError {
            throw deleteAccountError
        }
        deleteAccountCallCount += 1
        currentUserID = nil
        currentUserEmail = nil
    }
}
