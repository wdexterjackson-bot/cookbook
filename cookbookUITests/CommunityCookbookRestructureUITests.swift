//
//  CommunityCookbookRestructureUITests.swift
//  cookbookUITests
//
//  Manual verification for the Community Cookbook navigation/settings
//  restructure: tapping a Community Cookbook from Cookbooks now shows a
//  recipe-list-first view (empty state + Import while empty, real list
//  once populated), and cookbook/group property editing moved under
//  Administrator's two new "Manage Groups" / "Manage Community Cookbooks"
//  screens. Screenshots are attached at each checkpoint for visual review
//  rather than the test asserting a single pass/fail outcome end to end.
//

import XCTest

final class CommunityCookbookRestructureUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    func testCommunityCookbookNavigationAndAdminSettingsRestructure() throws {
        let app = XCUIApplication()
        app.launch()
        signOutIfAlreadySignedIn(app)

        let signUpSegment = app.buttons["Sign Up"]
        XCTAssertTrue(signUpSegment.waitForExistence(timeout: 10))
        signUpSegment.tap()

        let firstNameField = app.textFields["firstNameField"]
        XCTAssertTrue(firstNameField.waitForExistence(timeout: 5))
        firstNameField.tap()
        firstNameField.typeText("Restructure")

        let lastNameField = app.textFields["lastNameField"]
        lastNameField.tap()
        lastNameField.typeText("Tester")

        let emailField = app.textFields["emailField"]
        emailField.tap()
        emailField.typeText("restructure-\(Int(Date().timeIntervalSince1970))@example.com")

        let passwordField = app.secureTextFields["passwordField"]
        passwordField.tap()
        passwordField.typeText("TestPass123!")

        let submitButton = app.buttons["signInSubmitButton"]
        XCTAssertTrue(submitButton.isEnabled)
        submitButton.tap()

        let cookbooksTab = app.tabBars.buttons["Cookbooks"]
        XCTAssertTrue(cookbooksTab.waitForExistence(timeout: 20))
        XCTAssertTrue(tapWhenHittable(cookbooksTab, in: app))

        // --- Create a personal cookbook + one recipe (import source) ---
        let newCookbookMenu = app.buttons["New Cookbook"]
        XCTAssertTrue(newCookbookMenu.waitForExistence(timeout: 10))
        XCTAssertTrue(tapWhenHittable(newCookbookMenu, in: app))
        let newPersonalCookbook = app.buttons["New Personal Cookbook"]
        XCTAssertTrue(newPersonalCookbook.waitForExistence(timeout: 5))
        newPersonalCookbook.tap()
        let personalDone = app.buttons["Done"]
        XCTAssertTrue(personalDone.waitForExistence(timeout: 5))
        personalDone.tap()

        let myCookbookRow = app.buttons["My Cookbook"]
        XCTAssertTrue(myCookbookRow.waitForExistence(timeout: 10))
        XCTAssertTrue(tapWhenHittable(myCookbookRow, in: app))

        let addRecipeButton = app.buttons["Add Recipe"]
        XCTAssertTrue(addRecipeButton.waitForExistence(timeout: 10))
        addRecipeButton.tap()
        let titleField = app.textFields["Title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        titleField.tap()
        titleField.typeText("Skillet Cornbread")
        // A title alone isn't enough to save — the form requires at least
        // one ingredient or step (CreateEditRecipeView.save()'s own
        // validation), and a blank ingredient row is already present.
        let ingredientField = app.textFields["Ingredient"]
        XCTAssertTrue(ingredientField.waitForExistence(timeout: 5))
        ingredientField.tap()
        ingredientField.typeText("Cornmeal")
        app.buttons["Save"].tap()
        // Confirms Save actually dismissed the sheet (vs. accidentally
        // hitting Cancel) before navigating back to Cookbooks.
        XCTAssertTrue(app.staticTexts["Skillet Cornbread"].waitForExistence(timeout: 10), "Expected the saved recipe to appear in the personal cookbook's list")
        let backToCookbooks = app.navigationBars.buttons["Cookbooks"]
        XCTAssertTrue(backToCookbooks.waitForExistence(timeout: 5))
        backToCookbooks.tap()

        // --- Create a Community Cookbook ---
        XCTAssertTrue(tapWhenHittable(newCookbookMenu, in: app))
        let newCommunityCookbook = app.buttons["New Community Cookbook"]
        XCTAssertTrue(newCommunityCookbook.waitForExistence(timeout: 5))
        newCommunityCookbook.tap()

        let cookbookNameField = app.textFields.matching(NSPredicate(format: "placeholderValue BEGINSWITH 'Cookbook Name'")).firstMatch
        XCTAssertTrue(cookbookNameField.waitForExistence(timeout: 5))
        cookbookNameField.tap()
        cookbookNameField.typeText("Reunion 2026")
        let familyNameField = app.textFields.matching(NSPredicate(format: "placeholderValue BEGINSWITH 'Family, Group'")).firstMatch
        familyNameField.tap()
        familyNameField.typeText("Restructure Family")
        let locationField = app.textFields.matching(NSPredicate(format: "placeholderValue BEGINSWITH 'Home Location'")).firstMatch
        locationField.tap()
        locationField.typeText("Testville, TN\n") // dismiss the keyboard so any error Section below isn't hidden behind it
        // Disambiguate from the tab bar's own "Create" tab (plus.circle.fill).
        app.navigationBars["Create a Community Cookbook"].buttons["Create"].tap()
        // A fresh account gets launch-promo credits — the entitlement gate
        // asks to spend one before the group is actually created.
        let useCreditButton = app.buttons["Use Credit"]
        if useCreditButton.waitForExistence(timeout: 5) {
            useCreditButton.tap()
        }
        let createNavBar = app.navigationBars["Create a Community Cookbook"]
        XCTAssertTrue(
            createNavBar.waitForNonExistence(timeout: 20),
            "Create sheet never dismissed — visible text on screen: \(app.staticTexts.allElementsBoundByIndex.map(\.label))"
        )

        // --- Cookbooks tab: tap the Community Cookbook, expect empty state + Import ---
        // CookbooksHubView's joinedGroups only reloads via .task(id: userID)
        // or a manual pull-to-refresh — a freshly created cookbook doesn't
        // appear until one of those fires, so nudge it here.
        let communityCookbookRow = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Reunion 2026'")).firstMatch
        if !communityCookbookRow.waitForExistence(timeout: 3) {
            // A generic app.swipeDown() doesn't reliably trigger
            // SwiftUI's .refreshable — a slow drag from just below the
            // nav bar does.
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
            start.press(forDuration: 0.1, thenDragTo: end)
        }
        XCTAssertTrue(communityCookbookRow.waitForExistence(timeout: 10))
        XCTAssertTrue(tapWhenHittable(communityCookbookRow, in: app))

        let noRecipesYet = app.staticTexts["No Recipes Yet"]
        XCTAssertTrue(noRecipesYet.waitForExistence(timeout: 10), "Expected the personal-cookbook-style empty state")
        let importButton = app.buttons["Import Recipes from Existing Cookbook"]
        XCTAssertTrue(importButton.waitForExistence(timeout: 5), "Expected the Import action while the cookbook is empty")
        attachScreenshot(named: "01-community-cookbook-empty-state", of: app)

        // --- Import recipes from the personal cookbook we just made ---
        importButton.tap()
        let importNavTitle = app.navigationBars["Import Recipes"]
        XCTAssertTrue(importNavTitle.waitForExistence(timeout: 5))
        let sourcePicker = app.buttons["Cookbook, Choose a Cookbook"]
        if sourcePicker.waitForExistence(timeout: 3) {
            sourcePicker.tap()
            app.buttons["My Cookbook"].tap()
        }
        let importAction = app.buttons["Import"]
        XCTAssertTrue(importAction.waitForExistence(timeout: 5))
        importAction.tap()
        let doneAfterImport = app.buttons["Done"]
        XCTAssertTrue(doneAfterImport.waitForExistence(timeout: 15))
        doneAfterImport.tap()

        // --- Back on the Community Cookbook's recipe view: empty state and Import gone, recipe present ---
        XCTAssertTrue(app.staticTexts["Skillet Cornbread"].waitForExistence(timeout: 10), "Expected the imported recipe to now be listed")
        XCTAssertFalse(app.staticTexts["No Recipes Yet"].exists)
        XCTAssertFalse(app.buttons["Import Recipes from Existing Cookbook"].exists)
        attachScreenshot(named: "02-community-cookbook-with-recipe", of: app)

        // --- Administrator > Manage Groups ---
        let moreTab = app.tabBars.buttons["More"]
        XCTAssertTrue(moreTab.waitForExistence(timeout: 5))
        moreTab.tap()
        let administratorButton = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Administrator'")).firstMatch
        XCTAssertTrue(administratorButton.waitForExistence(timeout: 10))
        tapWhenHittable(administratorButton, in: app)

        let manageGroupsButton = app.buttons["Manage Groups"]
        XCTAssertTrue(manageGroupsButton.waitForExistence(timeout: 10))
        manageGroupsButton.tap()
        let groupRow = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Restructure Family'")).firstMatch
        XCTAssertTrue(groupRow.waitForExistence(timeout: 10))
        groupRow.tap()
        let saveGroupSettings = app.buttons["Save Group Settings"]
        XCTAssertTrue(saveGroupSettings.waitForExistence(timeout: 10), "Expected editable Group Settings as the founding admin")
        attachScreenshot(named: "03-manage-group-settings", of: app)

        // Back out to Administrator, then into Manage Community Cookbooks.
        let backToManageGroups = app.navigationBars.buttons["Manage Groups"]
        XCTAssertTrue(backToManageGroups.waitForExistence(timeout: 5))
        backToManageGroups.tap()
        app.navigationBars["Manage Groups"].buttons["Done"].tap() // dismiss Manage Groups sheet

        let manageCookbooksButton = app.buttons["Manage Community Cookbooks"]
        XCTAssertTrue(manageCookbooksButton.waitForExistence(timeout: 10))
        manageCookbooksButton.tap()
        XCTAssertTrue(app.staticTexts["Restructure Family"].waitForExistence(timeout: 10), "Expected the cookbook grouped under its parent group's name")
        let manageCookbookRow = app.buttons["Reunion 2026"]
        XCTAssertTrue(manageCookbookRow.waitForExistence(timeout: 5))
        manageCookbookRow.tap()
        // Cover Color/Style/Image sections push "Save Cookbook Settings"
        // below the fold — the List is lazy, so a row this far down isn't
        // even instantiated (let alone hittable) until scrolled into view.
        let saveCookbookSettings = app.buttons["Save Cookbook Settings"]
        for _ in 0..<4 where !saveCookbookSettings.exists {
            app.swipeUp()
        }
        XCTAssertTrue(saveCookbookSettings.waitForExistence(timeout: 10), "Expected editable Cookbook Settings as the founding admin")
        XCTAssertFalse(app.staticTexts["Skillet Cornbread"].exists, "Manage screen should show no recipes")
        attachScreenshot(named: "04-manage-cookbook-settings", of: app)
    }

    @MainActor
    private func attachScreenshot(named name: String, of app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
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
