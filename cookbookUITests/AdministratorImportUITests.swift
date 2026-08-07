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

        let profileTab = app.tabBars.buttons["Profile"]
        XCTAssertTrue(profileTab.waitForExistence(timeout: 20))
        profileTab.tap()
        dismissSavePasswordPromptIfPresent(app)

        let administratorButton = app.buttons["Administrator"]
        XCTAssertTrue(administratorButton.waitForExistence(timeout: 10))
        dismissSavePasswordPromptIfPresent(app)
        wait(for: [expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: administratorButton)], timeout: 5)
        administratorButton.tap()

        let importRow = app.buttons["Import Recipes from File"]
        XCTAssertTrue(importRow.waitForExistence(timeout: 10))
        importRow.tap()

        let chooseFileButton = app.buttons["Choose File"]
        let unavailableText = app.staticTexts["AI recipe import isn't available on this device — this needs Apple Intelligence turned on, which isn't supported in every region or on every device."]

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
        if notNow.waitForExistence(timeout: 2) {
            notNow.tap()
        }
    }

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
