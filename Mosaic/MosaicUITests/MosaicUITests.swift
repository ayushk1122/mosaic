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

        // The element spans the whole track; at the top of the board the bubble sits at its top.
        let frame = bubble.frame
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: frame.maxX - 18, dy: frame.minY + 18))
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
    func testLongPressMenuSetsOpacityAndShadow() throws {
        let app = XCUIApplication()
        app.launchArguments += ["UITestSkipLaunchAnimation"]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["mosaic.screen"].waitForExistence(timeout: 5))
        let plus = app.buttons["Add to Mosaic"]
        XCTAssertTrue(plus.waitForExistence(timeout: 3))
        plus.tap()
        let search = app.textFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 2))
        search.tap()
        search.typeText("draw")
        app.buttons["Draw"].tap()
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap()
        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 3))
        // A thick scribble, so the shadow has something to fall from.
        for offset in stride(from: 0.40, through: 0.50, by: 0.02) {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: offset))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: offset + 0.01)))
        }
        done.tap()
        XCTAssertTrue(done.waitForNonExistence(timeout: 2))

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).press(forDuration: 0.8)
        let look = app.buttons["Opacity and shadow"]
        XCTAssertTrue(look.waitForExistence(timeout: 3))
        look.tap()
        let slider = app.sliders.firstMatch
        XCTAssertTrue(slider.waitForExistence(timeout: 2))
        attachScreenshot(app, named: "Look panel")

        app.buttons["Shadow Lifted"].tap()
        slider.adjust(toNormalizedSliderPosition: 0.45)
        attachScreenshot(app, named: "Lifted at about half opacity")
        slider.adjust(toNormalizedSliderPosition: 1)
        app.buttons["White shadow"].tap()
        attachScreenshot(app, named: "Lifted white glow")

        // Close the menu and put the board back.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)).tap()
        XCTAssertTrue(slider.waitForNonExistence(timeout: 2), "Tapping off closes the panel")
        attachScreenshot(app, named: "Menu closed")
        let undo = app.buttons["Undo"]
        let drawing = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Drawing'")).firstMatch
        for _ in 0..<12 where drawing.exists && undo.isEnabled {
            undo.tap()
        }
        XCTAssertTrue(drawing.waitForNonExistence(timeout: 2))
    }

    @MainActor
    func testPhotoFrameStyles() throws {
        let app = XCUIApplication()
        app.launchArguments += ["UITestSkipLaunchAnimation"]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["mosaic.screen"].waitForExistence(timeout: 5))
        app.buttons["Add to Mosaic"].tap()
        let search = app.textFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 2))
        search.tap()
        search.typeText("media")
        app.buttons["Media"].tap()
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.3)).tap()

        // The multi-select picker: tap a photo in the grid (below the privacy banner when it's
        // shown), then confirm with the checkmark.
        let deadline = Date().addingTimeInterval(25)
        while app.images.count < 3, Date() < deadline { sleep(1) }
        guard app.images.count >= 3 else {
            attachScreenshot(app, named: "Picker without photos")
            throw XCTSkip("No photos in this simulator's library")
        }
        sleep(1)
        let banner = app.staticTexts["Private Access to Photos"].exists
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: banner ? 0.46 : 0.27)).tap()
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.905, dy: 0.153)).tap()
        // The picker hands the photo over in the background; give it time to land.
        sleep(10)
        attachScreenshot(app, named: "Photo placed")

        func openLook() {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.38)).press(forDuration: 0.8)
            let look = app.buttons["Opacity and shadow"]
            XCTAssertTrue(look.waitForExistence(timeout: 3))
            look.tap()
        }
        openLook()
        let polaroid = app.buttons["Frame Polaroid"]
        XCTAssertTrue(polaroid.waitForExistence(timeout: 2))
        polaroid.tap()
        let caption = app.buttons["Caption"]
        XCTAssertTrue(caption.waitForExistence(timeout: 2))
        caption.tap()
        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 2))
        field.typeText("Par 3")
        attachScreenshot(app, named: "Caption prompt")
        app.alerts.buttons["Save"].tap()
        attachScreenshot(app, named: "Polaroid with caption")
        app.buttons["Frame Tape"].tap()
        attachScreenshot(app, named: "Tape")
        app.buttons["Frame Torn"].tap()
        app.buttons["Shape Rounded"].tap()
        attachScreenshot(app, named: "Torn and rounded")
        app.buttons["Frame Polaroid"].tap()
        app.buttons["Shape Plain"].tap()

        // Tapping the photo itself closes its panel; no caption is needed. The panel sits above
        // or below the photo depending on room, so tap the photo on the other side of it.
        let panelTop = app.sliders.firstMatch.frame.minY / app.frame.height
        attachScreenshot(app, named: "Before tapping the photo")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: panelTop < 0.3 ? 0.44 : 0.34)).tap()
        XCTAssertTrue(app.sliders.firstMatch.waitForNonExistence(timeout: 2), "Tapping the piece closes its panel")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.88)).tap()
        sleep(1)
        attachScreenshot(app, named: "Polaroid on the board")

        let undo = app.buttons["Undo"]
        for _ in 0..<10 where undo.isEnabled {
            undo.tap()
        }
    }

    @MainActor
    func testEmojiStickerFromTheStickerSheet() throws {
        let app = XCUIApplication()
        app.launchArguments += ["UITestSkipLaunchAnimation"]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["mosaic.screen"].waitForExistence(timeout: 5))
        app.buttons["Add to Mosaic"].tap()
        let search = app.textFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 2))
        search.tap()
        search.typeText("sticker")
        app.buttons["Sticker"].tap()

        XCTAssertTrue(app.navigationBars["Stickers"].waitForExistence(timeout: 3))
        attachScreenshot(app, named: "Your stickers")
        app.buttons["Emoji"].tap()
        let golf = app.buttons["Emoji ⛳️"]
        XCTAssertTrue(golf.waitForExistence(timeout: 2))
        attachScreenshot(app, named: "Emoji tab")
        golf.tap()

        let sticker = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Sticker'")).firstMatch
        XCTAssertTrue(sticker.waitForExistence(timeout: 5))
        sleep(1)
        attachScreenshot(app, named: "Emoji sticker on the board")

        let undo = app.buttons["Undo"]
        if undo.isEnabled { undo.tap() }
        XCTAssertTrue(sticker.waitForNonExistence(timeout: 2))
    }

    @MainActor
    func testStickerCutoutFromALibraryPhoto() throws {
        let app = XCUIApplication()
        app.launchArguments += ["UITestSkipLaunchAnimation"]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["mosaic.screen"].waitForExistence(timeout: 5))
        app.buttons["Add to Mosaic"].tap()
        let search = app.textFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 2))
        search.tap()
        search.typeText("sticker")
        app.buttons["Sticker"].tap()
        let fromPhoto = app.buttons["From a photo"]
        XCTAssertTrue(fromPhoto.waitForExistence(timeout: 3))
        fromPhoto.tap()

        // The system photo picker; the simulator's library has sample photos.
        let deadline = Date().addingTimeInterval(25)
        while app.images.count < 3, Date() < deadline {
            sleep(1)
        }
        attachScreenshot(app, named: "Photo picker")
        guard app.images.count >= 3 else {
            throw XCTSkip("No photos in this simulator's library")
        }
        // The picker can show a banner with its own image first, so pick a grid cell.
        let cell = app.collectionViews.cells.element(boundBy: 1)
        if cell.waitForExistence(timeout: 5) {
            cell.tap()
        } else {
            app.images.element(boundBy: 2).tap()
        }

        let add = app.buttons["Add sticker"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        sleep(3)
        attachScreenshot(app, named: "Cutout editor")
        guard add.isEnabled else {
            throw XCTSkip("This simulator can't lift subjects (needs the Neural Engine)")
        }
        add.tap()
        let sticker = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Sticker'")).firstMatch
        XCTAssertTrue(sticker.waitForExistence(timeout: 5))
        sleep(1)
        attachScreenshot(app, named: "Sticker on the board")

        let undo = app.buttons["Undo"]
        if undo.isEnabled { undo.tap() }
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
