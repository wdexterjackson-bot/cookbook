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
    /// Set when PostSignInCoordinator.handle throws after a successful
    /// sign-in — the moment currentUserID is set below, AuthGatedRootView's
    /// @Observable diffing immediately swaps the whole view tree from the
    /// sign-in screen to RootTabView(), which would silently discard any
    /// @State error message a sign-in view is still in the middle of
    /// setting. Living here instead means the failure survives that swap
    /// regardless of which screen ends up mounted. Whoever reads this
    /// (RootTabView, on first appearance) is responsible for clearing it
    /// after showing it.
    var postSignInError: String?
    var currentUserEmail: String? { authService.currentUserEmail }
    var currentUserDisplayName: String? { authService.currentUserDisplayName }

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

    func sendPasswordReset(email: String) async throws {
        try await authService.sendPasswordReset(email: email)
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

    @discardableResult
    func signInWithCustomToken(_ token: String) async throws -> AuthResult {
        let result = try await authService.signInWithCustomToken(token)
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
