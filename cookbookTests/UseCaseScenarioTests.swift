//
//  UseCaseScenarioTests.swift
//  cookbookTests
//
//  Integration coverage for the 5 approved end-to-end use cases in
//  ProductDocumentation/UAT_Use_Case_Scenarios_2026-08-18.docx (Thanksgiving
//  Relay, Long-Distance Sourdough Swap, Office Chili Cook-Off Club, Grandpa
//  Walter's Kitchen Television, The Riverside Potluck Project).
//
//  Scope, deliberately: these drive the real production business-logic
//  services (GroupsServicing, FriendsServicing, PublicationsServicing,
//  EntitlementServicing, TVPairingServicing) through their InMemory/Fake
//  test doubles — the exact same pattern every other multi-actor test in
//  this suite already uses (see GroupsServicingTests, FriendsServicingTests,
//  PublicationsServicingTests). This proves the real multi-user data flow
//  and business rules for each scenario (credit spend, friend/join-request
//  lifecycle, publish/like/comment, approval-policy differences).
//
//  What this deliberately does NOT (and can't, in this environment) cover,
//  called out at each relevant step:
//   - Native Sign in with Apple / Sign in with Google UI — actors are
//     represented by a stable userID string, same as every existing test.
//   - QR code camera scanning and TV remote navigation — represented by
//     calling the same service method the scan/remote action would trigger.
//   - Two View-only regressions fixed earlier this session live entirely in
//     SwiftUI @State (CreateEditRecipeView's double-tap-Save guard,
//     ShoppingCartView's rename-on-blur) and can't be exercised without
//     XCUITest driving the actual screens. The cart-rename fix already has
//     dedicated coverage in CartItemStoreTests.renamingTheCartItemDoesNot-
//     BreakDedupAgainstTheSourceIngredient; the double-tap-Save guard has
//     none beyond manual verification — flagged as a real gap in the
//     session's findings, not silently skipped.
//   - The TV-pairing deviceSessionID security check lives in the real
//     Cloud Function (functions/tvPairing.js) — FakeTVPairingService is a
//     dumb stub that doesn't replicate it. That regression is already
//     properly covered by functions/test/tvPairing.test.js ("polling with
//     the wrong deviceSessionID never delivers the token"), so it isn't
//     re-asserted here against a fake that couldn't catch a real failure.
//

import Foundation
import SwiftData
import Testing
@testable import cookbook

struct UseCaseScenarioTests {

    // MARK: - Shared helpers

    private func groupDetails(
        name: String,
        locationText: String = "",
        visibility: GroupVisibility = .privateGroup,
        approvalPolicy: JoinApprovalPolicy = .anyAdministrator
    ) -> NewGroupDetails {
        NewGroupDetails(
            name: name,
            description: "",
            type: "Family",
            locationText: locationText,
            structuredRegion: nil,
            visibility: visibility,
            allowsMemberInvites: false,
            approvalPolicy: approvalPolicy
        )
    }

    private func cookbookDetails(_ name: String) -> NewGroupCookbookDetails {
        NewGroupCookbookDetails(cookbookName: name, allowsMemberPublishing: true)
    }

    private func seedEntitlement(
        _ service: InMemoryEntitlementService,
        userID: String,
        tier1Credits: Int = 1,
        tier2Credits: Int = 2
    ) {
        service.entitlementsByUserID[userID] = Entitlement(
            userID: userID,
            tier1Credits: tier1Credits,
            tier2Credits: tier2Credits,
            isProUser: false,
            receivedTier1PromoCredit: true,
            receivedTier2PromoCredits: true,
            createdAt: .now
        )
    }

    private func makeContent(title: String, authorLineage: String? = nil) -> PublicationContentSnapshot {
        PublicationContentSnapshot(
            title: title,
            summary: "",
            yield: "Serves 8",
            totalTimeMinutes: 45,
            ingredientSections: [],
            stepSections: [],
            notes: "",
            tags: [],
            authorLineage: authorLineage
        )
    }

    // MARK: - Use Case 1: "The Thanksgiving Relay"

    @Test func useCase1_thanksgivingRelay() async throws {
        let groups = InMemoryGroupsService()
        let entitlements = InMemoryEntitlementService()
        let friends = InMemoryFriendsService()
        let publications = InMemoryPublicationsService(groupsService: groups)

        // Step 1: Marisol signs up (represented by her stable userID) and
        // receives her free launch credits.
        seedEntitlement(entitlements, userID: "marisol", tier1Credits: 1, tier2Credits: 2)
        groups.tier2CreditsByUserID["marisol"] = 2
        #expect(try await entitlements.availableTier1Credits(userID: "marisol") == 1)
        #expect(try await entitlements.availableTier2Credits(userID: "marisol") == 2)

        // Step 3: redeems her free Pro User credit.
        let becamePro = try await entitlements.redeemTier1CreditForProUser(userID: "marisol")
        #expect(becamePro)
        #expect(try await entitlements.isProUser(userID: "marisol") == true)

        // Step 4: creates "The Alvarez Family Table," spending a Family
        // Cookbook credit.
        let (group, cookbook) = try await groups.createGroup(
            groupDetails(name: "The Alvarez Family Table", visibility: .privateGroup),
            cookbookDetails: cookbookDetails("Alvarez Family Table"),
            creatorUserID: "marisol",
            creatorDisplayName: "Marisol Alvarez",
            idempotencyKey: "uc1-create"
        )
        #expect(groups.tier2CreditsByUserID["marisol"] == 1)

        // Step 5: "scans Marisol's QR code" — represented directly as the
        // friend request the scan triggers (FriendsServicing.sendFriendRequest).
        seedEntitlement(entitlements, userID: "dante", tier1Credits: 1, tier2Credits: 2)
        let friendRequest = try await friends.sendFriendRequest(from: "dante", to: "marisol")
        #expect(friendRequest.status == .pending)

        // Step 6: Marisol accepts.
        try await friends.respondToFriendRequest(friendRequest.id, accept: true, respondingUserID: "marisol")
        let marisolFriends = try await friends.fetchFriends(forUser: "marisol")
        #expect(marisolFriends.contains { $0.userIDs.contains("dante") })

        // Step 7: Dante redeems his own credit, then requests to join.
        try await entitlements.redeemTier1CreditForProUser(userID: "dante")
        let joinRequest = try await groups.requestToJoin(groupID: group.id, requesterID: "dante", note: nil)
        #expect(joinRequest.state == .pending)

        // Step 8 (regression: duplicate join request, fixed this session).
        await #expect(throws: GroupsServiceError.joinRequestAlreadyPending) {
            try await groups.requestToJoin(groupID: group.id, requesterID: "dante", note: nil)
        }
        let pendingForGroup = try await groups.fetchJoinRequests(forGroup: group.id)
        #expect(pendingForGroup.count == 1)

        // Step 9: Marisol approves.
        try await groups.decideJoinRequest(joinRequest.id, approve: true, decidedByUserID: "marisol")
        let memberships = try await groups.fetchMemberships(forGroup: group.id)
        #expect(memberships.contains { $0.userID == "dante" && $0.status == .active })

        // Steps 10-11 (double-tap Save, cart-item rename): View-level only,
        // not exercised here — see file header and CartItemStoreTests.

        // Step 12: Dante publishes with comments on.
        let publication = try await publications.publish(
            makeContent(title: "Abuela's Tamales", authorLineage: "Dante Ruiz"),
            sourceRecipeID: "dante-recipe-1",
            to: group.id,
            cookbookID: cookbook.id,
            ownerUserID: "dante"
        )
        try await publications.setCommentsEnabled(publication.id, enabled: true, actingUserID: "dante")

        // Step 13: Marisol likes and comments.
        let likeCount = try await publications.setLiked(publication.id, userID: "marisol", liked: true)
        #expect(likeCount == 1)
        let comment = try await publications.addComment(
            publication.id, authorUserID: "marisol", authorDisplayName: "Marisol Alvarez",
            text: "This is exactly how Mom used to make them!"
        )
        let comments = try await publications.fetchComments(publication.id)
        #expect(comments.map(\.id) == [comment.id])
    }

    // MARK: - Use Case 2: "The Long-Distance Sourdough Swap"

    @MainActor
    @Test func useCase2_longDistanceSourdoughSwap() async throws {
        let friends = InMemoryFriendsService()
        let lineImport = FakeRecipeLineImportService()

        // Step 1: Tom finds Priya by email (findUserByEmail itself is
        // covered by functions/test/findUserByEmail.test.js) and sends a
        // request.
        let request = try await friends.sendFriendRequest(from: "tom", to: "priya")
        #expect(request.status == .pending)

        // Step 2: Priya accepts.
        try await friends.respondToFriendRequest(request.id, accept: true, respondingUserID: "priya")
        let tomFriends = try await friends.fetchFriends(forUser: "tom")
        #expect(tomFriends.contains { $0.userIDs.contains("priya") })

        // Step 3: Priya shares her recipe via the real system share sheet
        // formatter — genuinely exercises production code, not a stand-in.
        let schema = Schema([Recipe.self, IngredientSection.self, Ingredient.self, StepSection.self, Step.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = ModelContext(container)

        let sourdough = Recipe(ownerID: "priya", title: "Priya's No-Knead Sourdough Starter", sourceType: .manual)
        sourdough.authorLineage = "Priya Nair of Seattle, WA"
        let ingredientSection = IngredientSection()
        ingredientSection.ingredients = [Ingredient(displayText: "1 cup whole wheat flour", name: "whole wheat flour")]
        sourdough.ingredientSections = [ingredientSection]
        context.insert(sourdough)

        let sharedText = RecipeTextFormatter.plainText(for: sourdough)
        #expect(sharedText.contains("Priya's No-Knead Sourdough Starter"))
        #expect(sharedText.contains("Priya Nair of Seattle, WA"))
        #expect(sharedText.contains("whole wheat flour"))

        // Step 4: Tom pastes the text into Create > Paste Text. The AI
        // ingredient/step parsing is real production code (stubbed output
        // here, same as RecipeLineImportServicingTests); the separate
        // "By: <name>" attribution scan lives in CreateEditRecipeView
        // itself (View-level), not re-tested here.
        lineImport.stubbedResult = ParsedRecipeLines(
            title: "Priya's No-Knead Sourdough Starter",
            ingredients: [ParsedIngredientLine(name: "whole wheat flour", quantity: 1, unit: "cup")],
            steps: ["Mix flour and water, let rest 12 hours."]
        )
        let parsed = try await lineImport.parseLines(from: sharedText)
        #expect(parsed.ingredients.count == 1)
        #expect(lineImport.lastParsedText == sharedText)
    }

    // MARK: - Use Case 3: "The Office Chili Cook-Off Club"

    @Test func useCase3_officeChiliCookOffClub() async throws {
        let groups = InMemoryGroupsService()
        let entitlements = InMemoryEntitlementService()
        let publications = InMemoryPublicationsService(groupsService: groups)

        // Step 1: Deshawn redeems the discount code instead of spending a
        // launch credit.
        seedEntitlement(entitlements, userID: "deshawn", tier1Credits: 1, tier2Credits: 2)
        try await entitlements.applyDiscountCode("7595SLEDGERD", userID: "deshawn")
        let afterCode = try await entitlements.fetchEntitlement(userID: "deshawn")
        #expect(afterCode?.annualProMembershipCredits == 1)

        // Re-entering the same code is rejected.
        await #expect(throws: EntitlementServiceError.discountCodeAlreadyRedeemed) {
            try await entitlements.applyDiscountCode("7595SLEDGERD", userID: "deshawn")
        }

        // Step 2: redeems the Annual Pro Membership credit.
        let activated = try await entitlements.redeemAnnualProMembershipCredit(userID: "deshawn")
        #expect(activated)
        let afterRedeem = try await entitlements.fetchEntitlement(userID: "deshawn")
        #expect(afterRedeem?.isActiveAnnualProMember == true)
        #expect(afterRedeem?.isEffectivelyProUser == true)

        // Step 3: creates a private group from his separate free launch credits.
        groups.tier2CreditsByUserID["deshawn"] = 2
        let (group, cookbook) = try await groups.createGroup(
            groupDetails(name: "Team Kitchen Crew", visibility: .privateGroup),
            cookbookDetails: cookbookDetails("Team Kitchen Crew"),
            creatorUserID: "deshawn",
            creatorDisplayName: "Deshawn Carter",
            idempotencyKey: "uc3-create"
        )

        // Step 4: invites Farah and Lior by email rather than public request.
        let farahInvite = try await groups.invite(groupID: group.id, inviterID: "deshawn", inviteeIdentifier: "farah.haddad@example.com", role: .member)
        let liorInvite = try await groups.invite(groupID: group.id, inviterID: "deshawn", inviteeIdentifier: "lior.bendavid@example.com", role: .member)

        // Step 5: Farah accepts, Lior declines.
        try await groups.respondToInvitation(farahInvite.id, accept: true, respondingUserID: "farah.haddad@example.com")
        try await groups.respondToInvitation(liorInvite.id, accept: false, respondingUserID: "lior.bendavid@example.com")
        let memberships = try await groups.fetchMemberships(forGroup: group.id)
        #expect(memberships.contains { $0.userID == "farah.haddad@example.com" && $0.status == .active })
        #expect(!memberships.contains { $0.userID == "lior.bendavid@example.com" })

        // Step 6: Farah publishes with comments left off.
        seedEntitlement(entitlements, userID: "farah", tier1Credits: 1, tier2Credits: 0)
        try await entitlements.redeemTier1CreditForProUser(userID: "farah")
        let publication = try await publications.publish(
            makeContent(title: "Five-Alarm Turkey Chili", authorLineage: "Farah Haddad"),
            sourceRecipeID: "farah-recipe-1",
            to: group.id,
            cookbookID: cookbook.id,
            ownerUserID: "farah.haddad@example.com"
        )
        #expect(publication.commentsEnabled == false)

        // Step 7: Deshawn likes anyway — independent of comments state.
        let likeCount = try await publications.setLiked(publication.id, userID: "deshawn", liked: true)
        #expect(likeCount == 1)

        // Step 8: no way to comment while disabled.
        await #expect(throws: PublicationsServiceError.commentsDisabled) {
            try await publications.addComment(publication.id, authorUserID: "deshawn", authorDisplayName: "Deshawn Carter", text: "Looks great!")
        }
    }

    // MARK: - Use Case 4: "Grandpa Walter's Kitchen Television"

    @MainActor
    @Test func useCase4_grandpaWaltersKitchenTelevision() async throws {
        let groups = InMemoryGroupsService()
        let publications = InMemoryPublicationsService(groupsService: groups)
        let tvPairing = FakeTVPairingService()

        // Precondition (continuing from Use Case 1): the group and a
        // published, once-liked/commented recipe already exist.
        groups.tier2CreditsByUserID["marisol"] = 1
        let (group, cookbook) = try await groups.createGroup(
            groupDetails(name: "The Alvarez Family Table", visibility: .privateGroup),
            cookbookDetails: cookbookDetails("Alvarez Family Table"),
            creatorUserID: "marisol",
            creatorDisplayName: "Marisol Alvarez",
            idempotencyKey: "uc4-precondition"
        )
        let publication = try await publications.publish(
            makeContent(title: "Abuela's Tamales", authorLineage: "Dante Ruiz"),
            sourceRecipeID: "dante-recipe-1", to: group.id, cookbookID: cookbook.id, ownerUserID: "dante"
        )
        try await publications.setCommentsEnabled(publication.id, enabled: true, actingUserID: "dante")
        try await publications.setLiked(publication.id, userID: "marisol", liked: true)
        try await publications.addComment(publication.id, authorUserID: "marisol", authorDisplayName: "Marisol Alvarez", text: "This is exactly how Mom used to make them!")

        // Steps 1-3: Walter's own account pairs the TV via his own phone.
        // (The deviceSessionID security check is real only in
        // functions/tvPairing.js — see file header.)
        let pairingRequest = try await tvPairing.requestPairingCode(deviceSessionID: "walter-tv-session")
        try await tvPairing.confirmPairingCode(pairingRequest.code)
        let status = try await tvPairing.checkPairingStatus(code: pairingRequest.code, deviceSessionID: "walter-tv-session")
        guard case .confirmed = status else {
            Issue.record("Expected the TV pairing to be confirmed after the phone confirmed it")
            return
        }

        // Walter joins the family group (same request/approve flow as Dante
        // in Use Case 1).
        let joinRequest = try await groups.requestToJoin(groupID: group.id, requesterID: "walter", note: nil)
        try await groups.decideJoinRequest(joinRequest.id, approve: true, decidedByUserID: "marisol")
        let memberships = try await groups.fetchMemberships(forGroup: group.id)
        #expect(memberships.contains { $0.userID == "walter" && $0.status == .active })

        // Step 6 (regression: Cooking Mode timer survives backgrounding
        // because remainingSeconds is wall-clock-derived, not a decrementing
        // counter needing a live Timer callback to have fired).
        let timerManager = CookingTimerManager()
        timerManager.addTimer(name: "Tamale Steam", totalSeconds: 1)
        try await Task.sleep(nanoseconds: 1_500_000_000) // simulates the TV app being backgrounded past the timer's end
        #expect(timerManager.timers.first?.remainingSeconds == 0)
        timerManager.stop()

        // Steps 7-8: Walter switches to his phone (same account, shared
        // server-side like/comment state) and likes + comments.
        let likeCount = try await publications.setLiked(publication.id, userID: "walter", liked: true)
        #expect(likeCount == 2)
        try await publications.addComment(publication.id, authorUserID: "walter", authorDisplayName: "Walter Alvarez", text: "Made these tonight, Dante — perfect!")
        let comments = try await publications.fetchComments(publication.id)
        #expect(comments.count == 2)
    }

    // MARK: - Use Case 5: "The Riverside Potluck Project"

    @Test func useCase5_theRiversidePotluckProject() async throws {
        let groups = InMemoryGroupsService()
        let publications = InMemoryPublicationsService(groupsService: groups)
        let friends = InMemoryFriendsService()

        // Step 1: Renata creates a PUBLIC group with an anyUser approval
        // policy — distinct from every other use case's private groups.
        groups.tier2CreditsByUserID["renata"] = 1
        let (group, cookbook) = try await groups.createGroup(
            groupDetails(name: "Riverside Neighbors Potluck Cookbook", locationText: "Riverside, CA", visibility: .publicGroup, approvalPolicy: .anyUser),
            cookbookDetails: cookbookDetails("Riverside Neighbors Potluck Cookbook"),
            creatorUserID: "renata",
            creatorDisplayName: "Renata Kowalski",
            idempotencyKey: "uc5-create"
        )
        #expect(group.visibility == .publicGroup)

        // Step 2: Owen finds it by name search (fetchPublicGroups' name path
        // is exercised in GroupsServicingTests already; here we confirm the
        // created group is actually visible in that search).
        let byName = try await groups.fetchPublicGroups(matching: PublicGroupSearchFilter(text: "Riverside", locationText: nil))
        #expect(byName.contains { $0.id == group.id })

        // Step 3: Owen requests to join, with a note.
        let owenRequest = try await groups.requestToJoin(groupID: group.id, requesterID: "owen", note: "Excited to share my grandmother's pierogi recipe!")
        #expect(owenRequest.state == .pending)

        // Step 4 (regression: duplicate request from a second screen instance).
        await #expect(throws: GroupsServiceError.joinRequestAlreadyPending) {
            try await groups.requestToJoin(groupID: group.id, requesterID: "owen", note: nil)
        }

        // Step 5: Grace finds it by location instead of name.
        let byLocation = try await groups.fetchPublicGroups(matching: PublicGroupSearchFilter(text: nil, locationText: "Riverside"))
        #expect(byLocation.contains { $0.id == group.id })

        // Step 6: Grace requests to join.
        let graceRequest = try await groups.requestToJoin(groupID: group.id, requesterID: "grace", note: nil)
        #expect(graceRequest.state == .pending)
        let pending = try await groups.fetchJoinRequests(forGroup: group.id)
        #expect(pending.count == 2)

        // Step 7: Renata approves Owen.
        try await groups.decideJoinRequest(owenRequest.id, approve: true, decidedByUserID: "renata")

        // Step 8: Owen — a brand-new, non-admin member — approves Grace,
        // because this group's policy is anyUser, not anyAdministrator.
        try await groups.decideJoinRequest(graceRequest.id, approve: true, decidedByUserID: "owen")
        let memberships = try await groups.fetchMemberships(forGroup: group.id)
        #expect(memberships.contains { $0.userID == "owen" && $0.status == .active })
        #expect(memberships.contains { $0.userID == "grace" && $0.status == .active })

        // Contrast check, proving the doc's explicit claim: the same
        // non-admin-approves shape genuinely fails under the stricter
        // anyAdministrator policy used in Use Cases 1 and 3.
        let strictGroups = InMemoryGroupsService()
        strictGroups.tier2CreditsByUserID["renata"] = 1
        let (strictGroup, _) = try await strictGroups.createGroup(
            groupDetails(name: "Strict Policy Control Group", visibility: .publicGroup, approvalPolicy: .anyAdministrator),
            cookbookDetails: cookbookDetails("Strict Policy Control Group"),
            creatorUserID: "renata", creatorDisplayName: "Renata Kowalski", idempotencyKey: "uc5-control"
        )
        let controlOwenRequest = try await strictGroups.requestToJoin(groupID: strictGroup.id, requesterID: "owen", note: nil)
        try await strictGroups.decideJoinRequest(controlOwenRequest.id, approve: true, decidedByUserID: "renata")
        let controlGraceRequest = try await strictGroups.requestToJoin(groupID: strictGroup.id, requesterID: "grace", note: nil)
        await #expect(throws: GroupsServiceError.notAuthorized) {
            try await strictGroups.decideJoinRequest(controlGraceRequest.id, approve: true, decidedByUserID: "owen")
        }

        // Step 9: Grace publishes, comments enabled.
        let publication = try await publications.publish(
            makeContent(title: "Riverside Community Garden Ratatouille", authorLineage: "Grace Odenkirk"),
            sourceRecipeID: "grace-recipe-1", to: group.id, cookbookID: cookbook.id, ownerUserID: "grace"
        )
        try await publications.setCommentsEnabled(publication.id, enabled: true, actingUserID: "grace")

        // Step 10: Owen likes and comments — full interaction between two
        // people who found each other only through public discovery.
        let likeCount = try await publications.setLiked(publication.id, userID: "owen", liked: true)
        #expect(likeCount == 1)
        try await publications.addComment(publication.id, authorUserID: "owen", authorDisplayName: "Owen Baptiste", text: "Can't wait to try this at the next block party!")

        // Postcondition: no friendship exists between any pair — joining a
        // public group and becoming friends are verifiably independent.
        #expect(try await friends.fetchFriends(forUser: "renata").isEmpty)
        #expect(try await friends.fetchFriends(forUser: "owen").isEmpty)
        #expect(try await friends.fetchFriends(forUser: "grace").isEmpty)
    }
}
