//
//  PasswordRecoveryUITests.swift
//  cookbookUITests
//
//  Manual verification for the two new SignInView affordances: a show/hide
//  toggle on the password field, and "Forgot Password?" (Firebase's own
//  hosted reset-link email — real email, no account existence leaked by
//  its confirmation message, no plaintext password ever exposed).
//

import XCTest

final class PasswordRecoveryUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    func testPasswordVisibilityToggleAndForgotPassword() throws {
        let app = XCUIApplication()
        app.launch()
        signOutIfAlreadySignedIn(app)

        // Sign In is the default segment on a signed-out launch.
        let emailField = app.textFields["emailField"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 10))
        emailField.tap()
        emailField.typeText("forgot-password-test@example.com")

        // --- Eye toggle: starts hidden (SecureField), becomes plain text after tapping ---
        let secureField = app.secureTextFields["passwordField"]
        XCTAssertTrue(secureField.waitForExistence(timeout: 5), "Password field should start hidden")
        secureField.tap()
        secureField.typeText("SuperSecret1!")

        let showButton = app.buttons["Show password"]
        XCTAssertTrue(showButton.waitForExistence(timeout: 5))
        showButton.tap()

        let plainField = app.textFields["passwordField"]
        XCTAssertTrue(plainField.waitForExistence(timeout: 5), "Password field should become a plain TextField once revealed")
        XCTAssertEqual(plainField.value as? String, "SuperSecret1!")
        XCTAssertTrue(app.buttons["Hide password"].waitForExistence(timeout: 5))

        // --- Forgot Password: visible only in Sign In mode, sends and shows a confirmation ---
        let forgotPasswordButton = app.buttons["forgotPasswordButton"]
        XCTAssertTrue(forgotPasswordButton.waitForExistence(timeout: 10))
        XCTAssertTrue(forgotPasswordButton.isEnabled, "Should be enabled once an email is typed")
        XCTAssertTrue(tapWhenHittable(forgotPasswordButton, in: app))

        let confirmation = app.staticTexts["If an account exists for forgot-password-test@example.com, a password reset email is on its way."]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 15))

        // --- Forgot Password disappears in Sign Up mode ---
        XCTAssertTrue(tapWhenHittable(app.segmentedControls.buttons["Sign Up"], in: app))
        XCTAssertFalse(app.buttons["forgotPasswordButton"].exists, "Forgot Password only makes sense when signing in, not creating a new account")
    }

    @MainActor
    private func dismissSavePasswordPromptIfPresent(_ app: XCUIApplication) {
        let notNow = app.buttons["Not Now"]
        if notNow.waitForExistence(timeout: 1) {
            notNow.tap()
        }
    }

    /// iOS's own AutoFill "Save Password?" sheet can appear at any point
    /// after typing into a password field, covering the whole screen and
    /// blocking hit-testing on whatever's underneath — polls both
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

    @MainActor
    private func signOutIfAlreadySignedIn(_ app: XCUIApplication) {
        let moreTab = app.tabBars.buttons["More"]
        // 3s was too short on a slower cold launch (observed on iPad
        // Simulator: the tab bar isn't up yet at 3s even though the
        // account really is signed in) — falsely concluding "not signed
        // in" here strands every subsequent step, since the sign-up
        // screen never actually appears either.
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
