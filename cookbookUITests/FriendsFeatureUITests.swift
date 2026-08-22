//
//  FriendsFeatureUITests.swift
//  cookbookUITests
//
//  End-to-end coverage for the Friends feature (#5), run against the real
//  production Firebase project — same as every other UI test in this
//  suite, deliberately, since both bugs this file regression-tests
//  (firestore.rules denying the "are we already friends" read on a
//  friendship that doesn't exist yet, and findUserByEmail's case-sensitive
//  query) only ever showed up against the real backend, never against the
//  Fake/InMemory services cookbookTests exercises.
//
//  Deliberately NOT covered here: scanning a QR code end-to-end. Both
//  AddFriendView's camera-scan and email-search paths funnel into the
//  exact same `friendsService.sendFriendRequest` call with no sender/
//  recipient inversion between them (confirmed by reading AddFriendView
//  directly) — the QR bug's actual root cause was in firestore.rules'
//  friendships/read rule, shared infrastructure for both paths, not
//  anything QR-specific. Driving VisionKit's live camera scanner (or the
//  system document picker, for the "choose a QR image" fallback) from
//  XCUITest would be slow and flaky for zero additional coverage of the
//  actual bug — testDeclineThenResendThenAccept and
//  testSendRequestByEmailAcceptThenUnfriend below exercise the identical
//  sendFriendRequest → firestore.rules path the QR flow uses, and
//  rules-tests/rules.test.js's "reading a friendship that does not exist
//  yet succeeds" test is the direct regression test for that rule fix.
//
//  Also not covered, because the feature doesn't exist in this app today
//  (confirmed by exhaustive search, not an oversight): direct friend-to-
//  friend chat/messaging (the only "Messages" surface is the transactional
//  join-request/invitation/friend-request inbox exercised below, not a
//  free-text conversation), and any recipe-sharing capability unlocked by
//  being friends (recipes only ever move between users via Publish-to-a-
//  Community-Cookbook or Copy-to-Personal from one, regardless of
//  friendship status).
//

import XCTest

final class FriendsFeatureUITests: XCTestCase {
    private let testPassword = "TestPass123!"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Scenario 1: email search finds the user (bug #2 regression),
    // send, accept, both sides see the friendship, then unfriend.

    @MainActor
    func testSendRequestByEmailAcceptThenUnfriend() throws {
        let app = XCUIApplication()
        app.launch()
        signOutIfAlreadySignedIn(app)

        let emailA = "friend-a-\(Int(Date().timeIntervalSince1970))@example.com"
        signUp(firstName: "FriendA", lastName: "Tester", email: emailA, app: app)
        signOut(app)

        let emailB = "friend-b-\(Int(Date().timeIntervalSince1970))@example.com"
        signUp(firstName: "FriendB", lastName: "Tester", email: emailB, app: app)

        // B sends A a friend request by searching A's email — searched in
        // a different case than it was typed at sign-up, which is a
        // direct regression check for bug #2 (findUserByEmail's
        // case-sensitive query): if this still failed, "Send Friend
        // Request" would never appear and this line would time out.
        openAddFriend(app)
        searchByEmail(emailA.uppercased(), app: app)
        let sendRequestButton = app.buttons["Send Friend Request"]
        XCTAssertTrue(sendRequestButton.waitForExistence(timeout: 10), "Expected to find account A by email even with different casing")
        tapWhenHittable(sendRequestButton, in: app)
        XCTAssertTrue(app.staticTexts["Friend request sent."].waitForExistence(timeout: 10))
        closeAddFriendSheet(app)
        closeFriendsSheet(app)
        signOut(app)

        // A accepts B's request.
        signIn(email: emailA, password: testPassword, app: app)
        openMessages(app)
        let acceptButton = app.buttons["Accept"]
        XCTAssertTrue(acceptButton.waitForExistence(timeout: 10), "Expected an incoming friend request from B")
        // A raw .tap() right after waitForExistence was observed (twice)
        // to land on "Decline" instead — a mid-layout-settle mis-hit, not
        // a real app bug (confirmed: the exact same steps pass cleanly
        // once the tap waits for isHittable too, and rules-tests already
        // proves the accept -> friendship-creation path is correct at the
        // Firestore layer). tapWhenHittable's poll is what actually fixes
        // it; the screenshot is just a paper trail if it ever recurs.
        attach("before-accept-tap", app)
        tapWhenHittable(acceptButton, in: app)
        // A weak "Done still exists" check doesn't prove Accept actually
        // succeeded (that toolbar button is always there) — wait for the
        // request row itself to disappear (MessagesView reloads after a
        // successful respond) instead, and fail loudly on any error text.
        let acceptGone = app.buttons["Accept"]
        XCTAssertFalse(acceptGone.waitForExistence(timeout: 10), "Expected the accepted request to stop showing as pending")
        let messagesErrorMessage = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'couldn' OR label CONTAINS 'error' OR label CONTAINS 'Error'")).firstMatch
        XCTAssertFalse(messagesErrorMessage.exists, "Expected no error after accepting: \(messagesErrorMessage.label)")
        closeMessagesSheet(app)

        openFriends(app)
        let friendRow = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Member '")).firstMatch
        XCTAssertTrue(friendRow.waitForExistence(timeout: 10), "Expected the new friend to appear in A's Friends list")
        XCTAssertFalse(app.staticTexts["No friends yet — add one by email or QR code."].exists)

        // A removes the friendship.
        friendRow.swipeLeft()
        let removeButton = app.buttons["Remove"]
        XCTAssertTrue(removeButton.waitForExistence(timeout: 5))
        tapWhenHittable(removeButton, in: app)
        XCTAssertTrue(app.staticTexts["No friends yet — add one by email or QR code."].waitForExistence(timeout: 10), "Expected A's Friends list to be empty after removing")
        closeFriendsSheet(app)
        signOut(app)

        // The removal must be visible from B's side too — it's one shared
        // Firestore doc, not two independent ones, so a real bug here
        // would show up as B still seeing A as a friend.
        signIn(email: emailB, password: testPassword, app: app)
        openFriends(app)
        XCTAssertTrue(app.staticTexts["No friends yet — add one by email or QR code."].waitForExistence(timeout: 10), "Expected B's Friends list to also be empty after A removed the friendship")
    }

    // MARK: - Scenario 2: decline, then the original sender resends, then accept.

    @MainActor
    func testDeclineThenResendThenAccept() throws {
        let app = XCUIApplication()
        app.launch()
        signOutIfAlreadySignedIn(app)

        let emailC = "friend-c-\(Int(Date().timeIntervalSince1970))@example.com"
        signUp(firstName: "FriendC", lastName: "Tester", email: emailC, app: app)
        signOut(app)

        let emailD = "friend-d-\(Int(Date().timeIntervalSince1970))@example.com"
        signUp(firstName: "FriendD", lastName: "Tester", email: emailD, app: app)

        // D sends C a friend request.
        openAddFriend(app)
        searchByEmail(emailC, app: app)
        let sendRequestButton = app.buttons["Send Friend Request"]
        XCTAssertTrue(sendRequestButton.waitForExistence(timeout: 10))
        tapWhenHittable(sendRequestButton, in: app)
        XCTAssertTrue(app.staticTexts["Friend request sent."].waitForExistence(timeout: 10))
        closeAddFriendSheet(app)
        closeFriendsSheet(app)
        signOut(app)

        // C declines.
        signIn(email: emailC, password: testPassword, app: app)
        openMessages(app)
        let declineButton = app.buttons["Decline"]
        XCTAssertTrue(declineButton.waitForExistence(timeout: 10), "Expected an incoming friend request from D")
        tapWhenHittable(declineButton, in: app)
        XCTAssertTrue(app.navigationBars.buttons["Done"].waitForExistence(timeout: 10))
        // The declined request must actually be gone, not just re-rendered —
        // waiting for it to disappear catches a respondToFriendRequest bug
        // that leaves the doc looking pending.
        let acceptStillThere = app.buttons["Accept"]
        XCTAssertFalse(acceptStillThere.waitForExistence(timeout: 3), "Expected the declined request to no longer show as pending")
        closeMessagesSheet(app)
        signOut(app)

        // D resends — same Add Friend flow, same email, must succeed
        // (not report "already friends" or any other error) even though
        // a declined request already exists between them.
        signIn(email: emailD, password: testPassword, app: app)
        openAddFriend(app)
        searchByEmail(emailC, app: app)
        let resendButton = app.buttons["Send Friend Request"]
        XCTAssertTrue(resendButton.waitForExistence(timeout: 10))
        tapWhenHittable(resendButton, in: app)
        XCTAssertTrue(app.staticTexts["Friend request sent."].waitForExistence(timeout: 10), "Expected resending after a decline to succeed")
        XCTAssertFalse(app.staticTexts["You're already friends."].exists)
        closeAddFriendSheet(app)
        closeFriendsSheet(app)
        signOut(app)

        // C accepts the resent request.
        signIn(email: emailC, password: testPassword, app: app)
        openMessages(app)
        let acceptButton = app.buttons["Accept"]
        XCTAssertTrue(acceptButton.waitForExistence(timeout: 10), "Expected the resent request to show up as a fresh pending request")
        tapWhenHittable(acceptButton, in: app)
        closeMessagesSheet(app)

        openFriends(app)
        let friendRow = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Member '")).firstMatch
        XCTAssertTrue(friendRow.waitForExistence(timeout: 10), "Expected C and D to now be friends after decline -> resend -> accept")
    }

    // MARK: - Scenario 3: the sender cancels before the recipient responds.

    @MainActor
    func testCancelOutgoingRequestBeforeResponse() throws {
        let app = XCUIApplication()
        app.launch()
        signOutIfAlreadySignedIn(app)

        let emailE = "friend-e-\(Int(Date().timeIntervalSince1970))@example.com"
        signUp(firstName: "FriendE", lastName: "Tester", email: emailE, app: app)
        signOut(app)

        let emailF = "friend-f-\(Int(Date().timeIntervalSince1970))@example.com"
        signUp(firstName: "FriendF", lastName: "Tester", email: emailF, app: app)

        // F sends E a friend request, then cancels it before E ever responds.
        openAddFriend(app)
        searchByEmail(emailE, app: app)
        let sendRequestButton = app.buttons["Send Friend Request"]
        XCTAssertTrue(sendRequestButton.waitForExistence(timeout: 10))
        tapWhenHittable(sendRequestButton, in: app)
        XCTAssertTrue(app.staticTexts["Friend request sent."].waitForExistence(timeout: 10))
        closeAddFriendSheet(app)

        openMessages(app)
        let cancelButton = app.buttons["Cancel"]
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 10), "Expected F's own outgoing request to show up with a Cancel button")
        tapWhenHittable(cancelButton, in: app)
        let cancelGone = app.buttons["Cancel"]
        XCTAssertFalse(cancelGone.waitForExistence(timeout: 3), "Expected the cancelled outgoing request to disappear")
        closeMessagesSheet(app)
        closeFriendsSheet(app)
        signOut(app)

        // E must never have seen it (or must no longer see it after the cancel).
        signIn(email: emailE, password: testPassword, app: app)
        openMessages(app)
        XCTAssertFalse(app.buttons["Accept"].waitForExistence(timeout: 5), "Expected no incoming friend request for E after F cancelled")
    }

    // MARK: - Shared flow helpers

    @MainActor
    private func attach(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func signUp(firstName: String, lastName: String, email: String, app: XCUIApplication) {
        let signUpSegment = app.buttons["Sign Up"]
        XCTAssertTrue(signUpSegment.waitForExistence(timeout: 10))
        tapWhenHittable(signUpSegment, in: app)

        let firstNameField = app.textFields["firstNameField"]
        XCTAssertTrue(firstNameField.waitForExistence(timeout: 5))
        firstNameField.tap()
        firstNameField.typeText(firstName)

        let lastNameField = app.textFields["lastNameField"]
        lastNameField.tap()
        lastNameField.typeText(lastName)

        let emailField = app.textFields["emailField"]
        emailField.tap()
        emailField.typeText(email)

        let passwordField = app.secureTextFields["passwordField"]
        passwordField.tap()
        passwordField.typeText(testPassword)

        let submitButton = app.buttons["signInSubmitButton"]
        XCTAssertTrue(submitButton.isEnabled)
        submitButton.tap()

        let moreTab = app.tabBars.buttons["More"]
        XCTAssertTrue(moreTab.waitForExistence(timeout: 20), "Expected sign-up to land on the signed-in app")
    }

    @MainActor
    private func signIn(email: String, password: String, app: XCUIApplication) {
        let signInSegment = app.buttons["Sign In"]
        XCTAssertTrue(signInSegment.waitForExistence(timeout: 10))
        tapWhenHittable(signInSegment, in: app)

        let emailField = app.textFields["emailField"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 5))
        emailField.tap()
        emailField.typeText(email)

        let passwordField = app.secureTextFields["passwordField"]
        passwordField.tap()
        passwordField.typeText(password)

        let submitButton = app.buttons["signInSubmitButton"]
        XCTAssertTrue(submitButton.isEnabled)
        submitButton.tap()

        let moreTab = app.tabBars.buttons["More"]
        XCTAssertTrue(moreTab.waitForExistence(timeout: 20), "Expected sign-in to land on the signed-in app")
    }

    @MainActor
    private func signOut(_ app: XCUIApplication) {
        let moreTab = app.tabBars.buttons["More"]
        XCTAssertTrue(tapWhenHittable(moreTab, in: app))
        let profileCard = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Profile'")).firstMatch
        XCTAssertTrue(profileCard.waitForExistence(timeout: 10))
        profileCard.tap()
        let signOutButton = app.buttons["Sign Out"]
        XCTAssertTrue(signOutButton.waitForExistence(timeout: 10))
        signOutButton.tap()
    }

    @MainActor
    private func openAddFriend(_ app: XCUIApplication) {
        openFriends(app)
        let addFriendButton = app.buttons["Add Friend"]
        XCTAssertTrue(addFriendButton.waitForExistence(timeout: 10))
        tapWhenHittable(addFriendButton, in: app)
        XCTAssertTrue(app.navigationBars["Add Friend"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func searchByEmail(_ email: String, app: XCUIApplication) {
        let emailField = app.textFields["Friend's Email"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 5))
        emailField.tap()
        emailField.typeText(email)
        // "Search" also matches the app's own background tab bar item of
        // the same name (still present in the accessibility tree behind
        // this sheet, just not hittable) — app.buttons["Search"] is
        // therefore ambiguous; pick the one that's actually tappable.
        let searchButton = app.buttons.matching(NSPredicate(format: "label == 'Search'"))
            .allElementsBoundByIndex.first(where: { $0.isHittable })
        XCTAssertNotNil(searchButton, "Expected a hittable Search button")
        searchButton?.tap()
    }

    @MainActor
    private func closeAddFriendSheet(_ app: XCUIApplication) {
        let doneButton = app.navigationBars["Add Friend"].buttons["Done"]
        if doneButton.waitForExistence(timeout: 5) {
            doneButton.tap()
        }
    }

    @MainActor
    private func openFriends(_ app: XCUIApplication) {
        let moreTab = app.tabBars.buttons["More"]
        XCTAssertTrue(tapWhenHittable(moreTab, in: app))
        let friendsCard = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Friends'")).firstMatch
        XCTAssertTrue(friendsCard.waitForExistence(timeout: 10))
        tapWhenHittable(friendsCard, in: app)
        XCTAssertTrue(app.navigationBars["Friends"].waitForExistence(timeout: 10))
    }

    @MainActor
    private func closeFriendsSheet(_ app: XCUIApplication) {
        let doneButton = app.navigationBars["Friends"].buttons["Done"]
        if doneButton.waitForExistence(timeout: 5) {
            doneButton.tap()
        }
    }

    @MainActor
    private func openMessages(_ app: XCUIApplication) {
        let moreTab = app.tabBars.buttons["More"]
        XCTAssertTrue(tapWhenHittable(moreTab, in: app))
        let messagesCard = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Messages'")).firstMatch
        XCTAssertTrue(messagesCard.waitForExistence(timeout: 10))
        tapWhenHittable(messagesCard, in: app)
        XCTAssertTrue(app.navigationBars["Messages"].waitForExistence(timeout: 10))
    }

    @MainActor
    private func closeMessagesSheet(_ app: XCUIApplication) {
        let doneButton = app.navigationBars["Messages"].buttons["Done"]
        if doneButton.waitForExistence(timeout: 5) {
            doneButton.tap()
        }
    }

    /// iOS's own AutoFill "Save Password?" sheet can appear (on its own
    /// schedule, not tied to any one tap) after a sign-up or sign-in,
    /// covering the whole screen and blocking hit-testing on whatever's
    /// underneath — nothing to do with the app itself.
    @MainActor
    private func dismissSavePasswordPromptIfPresent(_ app: XCUIApplication) {
        let notNow = app.buttons["Not Now"]
        if notNow.waitForExistence(timeout: 1) {
            notNow.tap()
        }
    }

    @MainActor
    @discardableResult
    private func tapWhenHittable(_ element: XCUIElement, in app: XCUIApplication, timeout: TimeInterval = 15) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            dismissSavePasswordPromptIfPresent(app)
            if element.exists && element.isHittable {
                element.tap()
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        }
        return false
    }

    /// Firebase Auth's session survives app uninstall via the Simulator's
    /// Keychain, and persists for the rest of a `xcodebuild test` run
    /// across test methods/classes within the same launch — so a prior
    /// test's successful sign-up can leave this test looking at Home
    /// instead of the sign-up screen it needs. Sign out through the app's
    /// own UI to get back to a clean slate rather than depending on the
    /// simulator being erased externally before every run. A too-short
    /// timeout here (3s) was observed to falsely conclude "not signed in"
    /// on a slower cold launch (iPad Simulator) — 10s matches the fix
    /// applied to every other UI test file's copy of this helper.
    @MainActor
    private func signOutIfAlreadySignedIn(_ app: XCUIApplication) {
        let moreTab = app.tabBars.buttons["More"]
        guard moreTab.waitForExistence(timeout: 10) else { return }
        moreTab.tap()
        let profileCard = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Profile'")).firstMatch
        guard profileCard.waitForExistence(timeout: 3) else { return }
        profileCard.tap()
        let signOutButton = app.buttons["Sign Out"]
        guard signOutButton.waitForExistence(timeout: 3) else { return }
        signOutButton.tap()
    }
}
