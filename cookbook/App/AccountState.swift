//
//  AccountState.swift
//  cookbook
//
//  App-wide sign-in state, matching the reusable stack's @Observable +
//  .environment() convention. Wraps AuthServicing so views never touch
//  Firebase types directly.
//

import Foundation
import Observation

@MainActor
@Observable
final class AccountState {
    private let authService: AuthServicing

    private(set) var currentUserID: String?
    var currentUserEmail: String? { authService.currentUserEmail }
    var currentUserDisplayName: String? { authService.currentUserDisplayName }

    /// Set by SignInView right after PostSignInCoordinator reports a
    /// brand-new, promo-eligible account — AccountView shows the redemption
    /// prompt once and clears this. A stray "true" here is harmless (worst
    /// case the user sees the prompt again and it's a no-op if unavailable).
    var pendingFamilyUserPromoOffer = false

    var isSignedIn: Bool { currentUserID != nil }

    /// What new/changed Recipe.ownerID values should use: the signed-in
    /// account once there is one, otherwise the local guest identity.
    var currentOwnerID: String {
        currentUserID ?? LocalOwner.id
    }

    init(authService: AuthServicing) {
        self.authService = authService
        self.currentUserID = authService.currentUserID
    }

    @discardableResult
    func signIn(email: String, password: String) async throws -> AuthResult {
        let result = try await authService.signInWithEmail(email: email, password: password)
        currentUserID = result.userID
        return result
    }

    @discardableResult
    func signUp(email: String, password: String, displayName: String) async throws -> AuthResult {
        let result = try await authService.signUpWithEmail(email: email, password: password, displayName: displayName)
        currentUserID = result.userID
        return result
    }

    func updateDisplayName(_ displayName: String) async throws {
        try await authService.updateDisplayName(displayName)
    }

    @discardableResult
    func signInWithApple(idToken: String, rawNonce: String) async throws -> AuthResult {
        let result = try await authService.signInWithApple(idToken: idToken, rawNonce: rawNonce)
        currentUserID = result.userID
        return result
    }

    @discardableResult
    func signInWithGoogle(idToken: String, accessToken: String) async throws -> AuthResult {
        let result = try await authService.signInWithGoogle(idToken: idToken, accessToken: accessToken)
        currentUserID = result.userID
        return result
    }

    func signOut() throws {
        try authService.signOut()
        currentUserID = nil
    }

    func deleteAccount() async throws {
        try await authService.deleteAccount()
        currentUserID = nil
    }
}
