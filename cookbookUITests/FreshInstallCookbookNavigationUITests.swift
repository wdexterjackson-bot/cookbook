//
//  FreshInstallCookbookNavigationUITests.swift
//  cookbookUITests
//
//  Regression coverage for a reported bug: on a fresh install, tapping
//  "Personal Cookbook" appeared to pop up a screen and immediately return.
//  Root cause was RootTabView's first-run CookbookConfigurationView sheet,
//  auto-presented from a .task that could resolve right as the user
//  started navigating on their own — a race, not something reproducible
//  on a fixed schedule. This test doesn't reproduce the race directly;
//  it proves the destination is reachable end-to-end on a truly fresh
//  account, which is what the race used to interrupt.
//

import XCTest

final class FreshInstallCookbookNavigationUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testTappingPersonalCookbookAfterFreshSignUpReachesTheRecipeList() throws {
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
        emailField.typeText("fresh-\(Int(Date().timeIntervalSince1970))@example.com")

        let passwordField = app.secureTextFields["passwordField"]
        passwordField.tap()
        passwordField.typeText("TestPass123!")

        let submitButton = app.buttons["signInSubmitButton"]
        XCTAssertTrue(submitButton.isEnabled)
        submitButton.tap()

        let cookbooksTab = app.tabBars.buttons["Cookbooks"]
        XCTAssertTrue(cookbooksTab.waitForExistence(timeout: 20))
        cookbooksTab.tap()
        dismissSavePasswordPromptIfPresent(app)

        let personalCookbookRow = app.buttons["Personal Cookbook"]
        XCTAssertTrue(personalCookbookRow.waitForExistence(timeout: 10))
        dismissSavePasswordPromptIfPresent(app)
        // Existing isn't the same as hittable — the tab-switch transition
        // (or a delayed system "Save Password?" prompt) can still be
        // covering the row for a moment after the element appears.
        let isHittable = NSPredicate(format: "isHittable == true")
        wait(for: [expectation(for: isHittable, evaluatedWith: personalCookbookRow)], timeout: 5)
        personalCookbookRow.tap()

        // Landing on the recipe list (empty state, since this account has
        // no recipes yet) is the whole point — the race used to instead
        // pop the first-run config sheet on top of (or instead of) this.
        let emptyStateTitle = app.staticTexts["No Recipes Yet"]
        XCTAssertTrue(emptyStateTitle.waitForExistence(timeout: 10), "Expected to land on Personal Cookbook's recipe list")

        XCTAssertFalse(app.navigationBars["New Cookbook"].exists)
        XCTAssertFalse(app.navigationBars["Edit Cookbook"].exists)
    }

    /// iOS's own AutoFill "Save Password?" sheet can appear (on its own
    /// schedule, not tied to any one tap) after a fresh sign-up, covering
    /// the whole screen and blocking hit-testing on whatever's
    /// underneath — nothing to do with the app itself.
    @MainActor
    private func dismissSavePasswordPromptIfPresent(_ app: XCUIApplication) {
        let notNow = app.buttons["Not Now"]
        if notNow.waitForExistence(timeout: 2) {
            notNow.tap()
        }
    }

    /// Firebase Auth's session survives app uninstall via the Simulator's
    /// Keychain, and persists for the rest of a `xcodebuild test` run
    /// across test methods/classes within the same launch — so a prior
    /// test's successful sign-up can leave this test looking at Home
    /// instead of the sign-up screen it needs. Sign out through the app's
    /// own UI to get back to a clean slate rather than depending on the
    /// simulator being erased externally before every run.
    @MainActor
    private func signOutIfAlreadySignedIn(_ app: XCUIApplication) {
        let profileTab = app.tabBars.buttons["Profile"]
        guard profileTab.waitForExistence(timeout: 3) else { return }
        profileTab.tap()
        let signOutButton = app.buttons["Sign Out"]
        guard signOutButton.waitForExistence(timeout: 3) else { return }
        signOutButton.tap()
    }
}
