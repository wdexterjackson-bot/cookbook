//
//  SignInErrorMessagingTests.swift
//  cookbookTests
//

import FirebaseAuth
import Foundation
import Testing
@testable import cookbook

struct SignInErrorMessagingTests {

    private func authError(_ code: AuthErrorCode, email: String? = nil) -> NSError {
        var userInfo: [String: Any] = [:]
        if let email {
            userInfo[AuthErrors.userInfoEmailKey] = email
        }
        return NSError(domain: AuthErrors.domain, code: code.rawValue, userInfo: userInfo)
    }

    @Test func emailAlreadyInUseNeedsALookupUsingTheConflictEmail() {
        let error = authError(.emailAlreadyInUse, email: "taken@example.com")

        let classification = SignInErrorMessaging.classify(error, attemptedEmail: "typed@example.com", context: .signUp)

        #expect(classification == .needsProviderLookup(email: "taken@example.com", context: .signUp))
    }

    @Test func accountExistsWithDifferentCredentialNeedsALookup() {
        let error = authError(.accountExistsWithDifferentCredential, email: "taken@example.com")

        let classification = SignInErrorMessaging.classify(error, attemptedEmail: "typed@example.com", context: .signIn)

        #expect(classification == .needsProviderLookup(email: "taken@example.com", context: .signIn))
    }

    @Test func ambiguousInvalidCredentialFallsBackToTheAttemptedEmail() {
        let error = authError(.invalidCredential)

        let classification = SignInErrorMessaging.classify(error, attemptedEmail: "typed@example.com", context: .signIn)

        #expect(classification == .needsProviderLookup(email: "typed@example.com", context: .signIn))
    }

    @Test func unrelatedErrorsShowImmediately() {
        let error = authError(.networkError)

        let classification = SignInErrorMessaging.classify(error, attemptedEmail: "typed@example.com", context: .signIn)

        guard case .immediateMessage = classification else {
            Issue.record("expected an immediate message")
            return
        }
    }

    @Test func signUpMessageNamesTheExistingProvider() {
        let message = SignInErrorMessaging.message(for: .exists(providers: [.google]), context: .signUp)
        #expect(message.contains("Google"))
    }

    @Test func signInMessagePrefersIncorrectPasswordWhenAPasswordAccountExists() {
        let message = SignInErrorMessaging.message(for: .exists(providers: [.password]), context: .signIn)
        #expect(message == "Incorrect password for this email.")
    }

    @Test func signInMessageNamesTheOtherProviderWhenNoPasswordAccountExists() {
        let message = SignInErrorMessaging.message(for: .exists(providers: [.apple]), context: .signIn)
        #expect(message.contains("Apple"))
    }

    @Test func signInNotFoundIsGeneric() {
        let message = SignInErrorMessaging.message(for: .notFound, context: .signIn)
        #expect(message == "No account found for this email.")
    }
}
