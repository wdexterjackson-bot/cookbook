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
        XCTAssertTrue(tapWhenHittable(cookbooksTab, in: app))

        let personalCookbookRow = app.buttons["Personal Cookbook"]
        XCTAssertTrue(personalCookbookRow.waitForExistence(timeout: 10))
        XCTAssertTrue(tapWhenHittable(personalCookbookRow, in: app))

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
        if notNow.waitForExistence(timeout: 1) {
            notNow.tap()
        }
    }

    /// A single dismiss check right before tapping can still miss the
    /// AutoFill sheet if it appears mid-wait instead — polls both
    /// conditions together until the target element is actually tappable
    /// (or the timeout elapses), tapping it the moment it is.
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
    /// simulator being erased externally before every run.
    ///
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
