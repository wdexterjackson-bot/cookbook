//
//  AuthServicingTests.swift
//  cookbookTests
//

import Foundation
import Testing
@testable import cookbook

struct AuthServicingTests {

    @Test func signUpCreatesANewAccount() async throws {
        let service = FakeAuthService()

        let result = try await service.signUpWithEmail(email: "cook@example.com", password: "hunter2", displayName: "Cook Example")

        #expect(result.isNewAccount == true)
        #expect(service.currentUserID == result.userID)
    }

    @Test func signInToExistingAccountIsNotNew() async throws {
        let service = FakeAuthService()
        _ = try await service.signUpWithEmail(email: "cook@example.com", password: "hunter2", displayName: "Cook Example")
        try service.signOut()

        let result = try await service.signInWithEmail(email: "cook@example.com", password: "hunter2")

        #expect(result.isNewAccount == false)
    }

    @Test func signInToUnknownEmailThrows() async throws {
        let service = FakeAuthService()

        await #expect(throws: AuthServiceError.self) {
            try await service.signInWithEmail(email: "nobody@example.com", password: "whatever")
        }
    }

    @Test func federatedSignInIsNewOnlyOnFirstUseOfAToken() async throws {
        let service = FakeAuthService()

        let first = try await service.signInWithApple(idToken: "token-abc", rawNonce: "nonce")
        try service.signOut()
        let second = try await service.signInWithApple(idToken: "token-abc", rawNonce: "nonce")

        #expect(first.isNewAccount == true)
        #expect(second.isNewAccount == false)
        #expect(first.userID == second.userID)
    }

    @Test func signOutClearsCurrentUser() async throws {
        let service = FakeAuthService()
        _ = try await service.signUpWithEmail(email: "cook@example.com", password: "hunter2", displayName: "Cook Example")

        try service.signOut()

        #expect(service.currentUserID == nil)
    }

    @Test func deleteAccountRequiresBeingSignedIn() async throws {
        let service = FakeAuthService()

        await #expect(throws: AuthServiceError.self) {
            try await service.deleteAccount()
        }
    }
}
