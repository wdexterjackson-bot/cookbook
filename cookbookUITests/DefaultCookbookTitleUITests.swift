//
//  DefaultCookbookTitleUITests.swift
//  cookbookUITests
//
//  Manual verification: creating a first personal cookbook still defaults
//  its title to "My Cookbook", but creating a second one while a "My
//  Cookbook" already exists leaves the title blank (with a footer prompt)
//  instead of silently offering the same taken name again.
//

import XCTest

final class DefaultCookbookTitleUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    func testSecondCookbookDoesNotReuseTheDefaultTitle() throws {
        let app = XCUIApplication()
        app.launch()
        signOutIfAlreadySignedIn(app)

        let signUpSegment = app.buttons["Sign Up"]
        XCTAssertTrue(signUpSegment.waitForExistence(timeout: 10))
        signUpSegment.tap()
        app.textFields["firstNameField"].tap()
        app.textFields["firstNameField"].typeText("Default")
        app.textFields["lastNameField"].tap()
        app.textFields["lastNameField"].typeText("Title")
        app.textFields["emailField"].tap()
        app.textFields["emailField"].typeText("default-title-\(Int(Date().timeIntervalSince1970))@example.com")
        app.secureTextFields["passwordField"].tap()
        app.secureTextFields["passwordField"].typeText("TestPass123!")
        app.buttons["signInSubmitButton"].tap()

        let cookbooksTab = app.tabBars.buttons["Cookbooks"]
        XCTAssertTrue(cookbooksTab.waitForExistence(timeout: 20))
        tapWhenHittable(cookbooksTab, in: app)

        // --- First personal cookbook: still defaults to "My Cookbook" ---
        let newCookbookMenu = app.buttons["New Cookbook"]
        XCTAssertTrue(newCookbookMenu.waitForExistence(timeout: 10))
        tapWhenHittable(newCookbookMenu, in: app)
        app.buttons["New Personal Cookbook"].tap()

        let titleField = app.textFields["Cookbook Title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        XCTAssertEqual(titleField.value as? String, "My Cookbook", "First cookbook should still default to My Cookbook")
        tapWhenHittable(app.buttons["Done"], in: app)

        // --- Second personal cookbook: title should be blank, with the collision footer shown ---
        tapWhenHittable(newCookbookMenu, in: app)
        app.buttons["New Personal Cookbook"].tap()

        let secondTitleField = app.textFields["Cookbook Title"]
        XCTAssertTrue(secondTitleField.waitForExistence(timeout: 5))
        XCTAssertEqual(secondTitleField.value as? String, "Cookbook Title", "Placeholder shows (empty value) once My Cookbook is already taken")
        XCTAssertTrue(app.staticTexts["You already have a cookbook named \"My Cookbook\" — give this one its own name."].waitForExistence(timeout: 5))

        secondTitleField.tap()
        secondTitleField.typeText("Second Cookbook")
        tapWhenHittable(app.buttons["Done"], in: app)

        XCTAssertTrue(app.buttons["Second Cookbook"].waitForExistence(timeout: 10))
    }

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
