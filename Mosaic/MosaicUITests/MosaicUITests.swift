//
//  MosaicUITests.swift
//  MosaicUITests
//
//  Created by Ayush Krishnappa on 9/28/26.
//

import XCTest

final class MosaicUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testLaunchShowsThreeTabShellWithMosaicSelected() throws {
        let app = XCUIApplication()
        app.launchArguments += ["UITestSkipLaunchAnimation"]
        app.launch()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["mosaic.screen"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Mosaic"].waitForExistence(timeout: 2))

        for title in ["Mosaic", "Circle", "Discover"] {
            XCTAssertTrue(tabBar.buttons[title].exists)
        }
        XCTAssertFalse(tabBar.buttons["Feed"].exists)

        tabBar.buttons["Circle"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["circle.screen"].waitForExistence(timeout: 2))

        tabBar.buttons["Discover"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["search.screen"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 2))
    }

    @MainActor
    func testCircleAndDiscoverOfferOnlyABackground() throws {
        let app = XCUIApplication()
        app.launchArguments += ["UITestSkipLaunchAnimation"]
        app.launch()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        for title in ["Discover", "Circle"] {
            tabBar.buttons[title].tap()
            let plus = app.buttons["composer.addButton"]
            XCTAssertTrue(plus.waitForExistence(timeout: 2))
            plus.tap()
            let background = app.buttons["composer.add.background"]
            XCTAssertTrue(background.waitForExistence(timeout: 2))
            XCTAssertFalse(app.textFields["composer.add.search"].exists)
            XCTAssertFalse(app.buttons["composer.add.text"].exists)
            attachScreenshot(app, named: "\(title) menu")
            background.tap()
            XCTAssertTrue(app.navigationBars["Background"].waitForExistence(timeout: 2))
            if title == "Discover" {
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.62, dy: 0.53)).tap()
            }
            attachScreenshot(app, named: "\(title) editor")
            app.navigationBars["Background"].buttons["Done"].tap()
            attachScreenshot(app, named: "\(title) page")
        }
    }

    @MainActor
    func testScrollBubbleMovesTheBoardInEditModeOnly() throws {
        let app = XCUIApplication()
        app.launchArguments += ["UITestSkipLaunchAnimation"]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["mosaic.screen"].waitForExistence(timeout: 5))
        // The screen's identifier covers its children's, so the bubble is found by its label.
        let bubble = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Scroll board'")).firstMatch
        XCTAssertTrue(bubble.waitForExistence(timeout: 3))
        XCTAssertEqual(bubble.value as? String, "0 percent")
        attachScreenshot(app, named: "Scroll bubble at the top")

        let frame = bubble.frame
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: frame.midX, dy: frame.midY))
        let end = origin.withOffset(CGVector(dx: frame.midX, dy: app.frame.height - 120))
        start.press(forDuration: 0.1, thenDragTo: end)
        attachScreenshot(app, named: "Scroll bubble dragged to the bottom")
        XCTAssertEqual(bubble.value as? String, "100 percent")

        app.buttons["View Mosaic"].tap()
        XCTAssertTrue(bubble.waitForNonExistence(timeout: 2))
        attachScreenshot(app, named: "No scroll bubble in view mode")
    }

    @MainActor
    func testDrawPieceTakesFingerInkAndStaysAfterDone() throws {
        let app = XCUIApplication()
        app.launchArguments += ["UITestSkipLaunchAnimation"]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["mosaic.screen"].waitForExistence(timeout: 5))
        // The screen's identifier covers its children's, so controls are found by label.
        let plus = app.buttons["Add to Mosaic"]
        XCTAssertTrue(plus.waitForExistence(timeout: 3))
        plus.tap()
        let search = app.textFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 2))
        search.tap()
        search.typeText("draw")
        let draw = app.buttons["Draw"]
        XCTAssertTrue(draw.waitForExistence(timeout: 2))
        draw.tap()

        // Drop the piece mid-screen; it opens straight into drawing.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap()
        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 3))
        attachScreenshot(app, named: "Drawing open")

        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.42))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.48))
        start.press(forDuration: 0.05, thenDragTo: end)
        attachScreenshot(app, named: "After a stroke")

        done.tap()
        XCTAssertTrue(done.waitForNonExistence(timeout: 2))
        let drawing = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Drawing'")).firstMatch
        XCTAssertTrue(drawing.waitForExistence(timeout: 2), "A drawing with ink stays on the board after Done")
        attachScreenshot(app, named: "After Done")

        // Tapping the drawing opens it for drawing again.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap()
        let reopened = done.waitForExistence(timeout: 3)
        attachScreenshot(app, named: "Drawing reopened")
        XCTAssertTrue(reopened, "Tapping a drawing opens it for drawing")
        done.tap()
        XCTAssertTrue(done.waitForNonExistence(timeout: 2))

        let undo = app.buttons["Undo"]
        for _ in 0..<4 where drawing.exists && undo.isEnabled {
            undo.tap()
        }
        XCTAssertTrue(drawing.waitForNonExistence(timeout: 2))
    }

    @MainActor
    private func attachScreenshot(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
