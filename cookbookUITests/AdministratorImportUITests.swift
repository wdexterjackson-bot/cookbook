//
//  AdministratorImportUITests.swift
//  cookbookUITests
//
//  Manual verification test for the Administrator screen / bulk import
//  flow — not meant to be a permanent regression test (see the assertions
//  below, which report state rather than assert a single expected
//  outcome, since on-device AI availability is environment-dependent).
//

import XCTest

final class AdministratorImportUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testNavigateToAdministratorImportScreen() throws {
        let app = XCUIApplication()
        app.launch()
        signOutIfAlreadySignedIn(app)

        let signUpSegment = app.buttons["Sign Up"]
        XCTAssertTrue(signUpSegment.waitForExistence(timeout: 10))
        signUpSegment.tap()

        let firstNameField = app.textFields["firstNameField"]
        XCTAssertTrue(firstNameField.waitForExistence(timeout: 5))
        firstNameField.tap()
        firstNameField.typeText("Fresh")

        let lastNameField = app.textFields["lastNameField"]
        lastNameField.tap()
        lastNameField.typeText("Tester")

        let emailField = app.textFields["emailField"]
        emailField.tap()
        emailField.typeText("admin-import-\(Int(Date().timeIntervalSince1970))@example.com")

        let passwordField = app.secureTextFields["passwordField"]
        passwordField.tap()
        passwordField.typeText("TestPass123!")

        let submitButton = app.buttons["signInSubmitButton"]
        XCTAssertTrue(submitButton.isEnabled)
        submitButton.tap()

        let moreTab = app.tabBars.buttons["More"]
        XCTAssertTrue(moreTab.waitForExistence(timeout: 20))
        XCTAssertTrue(tapWhenHittable(moreTab, in: app))

        // Administrator is a direct card on the More hub (see
        // MoreHubView) — its accessibility label is combined with its
        // subtitle ("Administrator. Bulk recipe import"), so match on a
        // prefix rather than the exact title.
        let administratorButton = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Administrator'")).firstMatch
        XCTAssertTrue(administratorButton.waitForExistence(timeout: 10))
        XCTAssertTrue(tapWhenHittable(administratorButton, in: app))

        let importRow = app.buttons["Import Recipes from File"]
        XCTAssertTrue(importRow.waitForExistence(timeout: 10))
        importRow.tap()

        let chooseFileButton = app.buttons["Choose File"]
        let unavailableText = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "isn't available on this device")).firstMatch

        print("DEBUG_STATE_START")
        if chooseFileButton.waitForExistence(timeout: 8) {
            print("DEBUG_STATE: Choose File button IS present — on-device AI is available.")
        } else if unavailableText.waitForExistence(timeout: 2) {
            print("DEBUG_STATE: Unavailable message IS shown — on-device AI is NOT available in this environment.")
        } else {
            print("DEBUG_STATE: Neither element found — unexpected state.")
            print(app.debugDescription)
        }
        print("DEBUG_STATE_END")

        XCTAssertTrue(chooseFileButton.exists || unavailableText.exists, "Expected either the Choose File button or the unavailable message.")
    }

    @MainActor
    private func dismissSavePasswordPromptIfPresent(_ app: XCUIApplication) {
        let notNow = app.buttons["Not Now"]
        if notNow.waitForExistence(timeout: 1) {
            notNow.tap()
        }
    }

    /// iOS's own AutoFill "Save Password?" sheet can appear at any point
    /// after a fresh sign-up, on its own schedule, covering the whole
    /// screen and blocking hit-testing on whatever's underneath — a
    /// single dismiss check before tapping can miss it if it shows up
    /// mid-wait instead. Polls both conditions together until the target
    /// element is actually tappable (or the timeout elapses), tapping it
    /// the moment it is.
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

    /// Profile is no longer a direct tab bar item — it's reached through
    /// the "More" hub, which groups it with Messages/Administrator/
    /// Discover behind icon-badge cards rather than plain rows (see
    /// MoreHubView). Card buttons carry a combined accessibility label
    /// ("Profile. Account & purchases"), so match on a prefix rather than
    /// the exact title.
    @MainActor
    private func signOutIfAlreadySignedIn(_ app: XCUIApplication) {
        let moreTab = app.tabBars.buttons["More"]
        guard moreTab.waitForExistence(timeout: 3) else { return }
        moreTab.tap()
        let profileCard = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Profile'")).firstMatch
        guard profileCard.waitForExistence(timeout: 3) else { return }
        profileCard.tap()
        let signOutButton = app.buttons["Sign Out"]
        guard signOutButton.waitForExistence(timeout: 3) else { return }
        signOutButton.tap()
    }
}
