//
//  ErrorMessagingTests.swift
//  cookbookTests
//
//  Cheap regression coverage against an error case being added later
//  without a message: before this pass, none of these eight enums
//  conformed to LocalizedError at all, so any generic
//  `catch { errorMessage = error.localizedDescription }` not specifically
//  pattern-matched against a known case showed Swift's ugly auto-generated
//  bridging string (e.g. "The operation couldn't be completed. (cookbook.
//  PublicationsServiceError error 2.)") instead of a real message.
//

import Foundation
import Testing
@testable import cookbook

struct ErrorMessagingTests {

    /// True for Swift's auto-generated bridging string, false for a real,
    /// hand-written message — the exact shape LocalizedError conformance
    /// exists to prevent reaching the UI.
    private func isGenericBridgingMessage(_ message: String) -> Bool {
        message.contains("The operation couldn’t be completed") || message.contains("The operation couldn't be completed")
    }

    private func assertAllCasesHaveRealMessages(_ errors: [Error]) {
        for error in errors {
            let message = error.localizedDescription
            #expect(!message.isEmpty)
            #expect(!isGenericBridgingMessage(message), "\(error) fell back to the generic bridging message")
        }
    }

    @Test func publicationsServiceErrorHasRealMessages() {
        assertAllCasesHaveRealMessages([
            PublicationsServiceError.publicationNotFound, .commentNotFound, .commentsDisabled, .notAuthorized,
        ])
    }

    @Test func groupsServiceErrorHasRealMessages() {
        assertAllCasesHaveRealMessages([
            GroupsServiceError.insufficientCredits, .creditExpired, .groupNotFound, .groupCookbookNotFound,
            .membershipNotFound, .joinRequestNotFound, .invitationNotFound, .notAuthorized,
            .lastAdminCannotLeaveOrBeDemoted, .alreadyMember, .invalidState,
        ])
    }

    @Test func friendsServiceErrorHasRealMessages() {
        assertAllCasesHaveRealMessages([
            FriendsServiceError.requestNotFound, .notAuthorized, .invalidState, .alreadyFriends,
        ])
    }

    @Test func authServiceErrorHasRealMessages() {
        assertAllCasesHaveRealMessages([
            AuthServiceError.notSignedIn, .invalidCredential, .requiresRecentLogin,
        ])
    }

    @Test func entitlementServiceErrorHasRealMessages() {
        assertAllCasesHaveRealMessages([
            EntitlementServiceError.creditExpired, .invalidDiscountCode, .discountCodeAlreadyRedeemed,
        ])
    }

    @Test func messagingServiceErrorHasRealMessages() {
        assertAllCasesHaveRealMessages([
            MessagingServiceError.messageNotFound, .notAuthorized,
        ])
    }

    @Test func purchaseServiceErrorHasRealMessages() {
        assertAllCasesHaveRealMessages([
            PurchaseServiceError.productNotFound, .verificationFailed, .claimSubmissionFailed,
        ])
    }

    @Test func tvPairingServiceErrorHasRealMessages() {
        assertAllCasesHaveRealMessages([
            TVPairingServiceError.malformedResponse,
        ])
    }
}
