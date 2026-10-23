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

        for title in ["Mosaic", "Explore", "Circle", "Discover"] {
            XCTAssertTrue(tabBar.buttons[title].exists)
        }
        XCTAssertFalse(tabBar.buttons["Feed"].exists)

        // Signed out (as UI tests run), Explore explains it needs an account.
        tabBar.buttons["Explore"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["explore.screen"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Sign in to explore other people's Mosaics."].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["explore.filter.all"].exists)

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

        // VoiceOver's box is the bubble itself, so it's grabbed at its center.
        let frame = bubble.frame
        XCTAssertLessThan(frame.height, 120, "The accessibility frame is the bubble, not the whole track")
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
        // Faded and shadowed, the frame and photo should read as one piece of paper.
        app.buttons["Shadow Lifted"].tap()
        app.sliders.firstMatch.adjust(toNormalizedSliderPosition: 0.5)
        attachScreenshot(app, named: "Polaroid lifted at half opacity")
        app.sliders.firstMatch.adjust(toNormalizedSliderPosition: 1)
        app.buttons["Shadow None"].tap()
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
    func testFullScreenPhotoPinchesToZoom() throws {
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
        let deadline = Date().addingTimeInterval(25)
        while app.images.count < 3, Date() < deadline { sleep(1) }
        guard app.images.count >= 3 else { throw XCTSkip("No photos in this simulator's library") }
        sleep(1)
        let banner = app.staticTexts["Private Access to Photos"].exists
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: banner ? 0.46 : 0.27)).tap()
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.905, dy: 0.153)).tap()
        sleep(10)

        // In view mode, a tap opens the photo full screen.
        app.buttons["View Mosaic"].tap()
        sleep(1)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.36)).tap()
        let viewer = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Photo'")).firstMatch
        XCTAssertTrue(viewer.waitForExistence(timeout: 3))
        attachScreenshot(app, named: "Full screen")

        viewer.pinch(withScale: 3, velocity: 2)
        sleep(1)
        attachScreenshot(app, named: "Pinched in")
        XCTAssertTrue((viewer.value as? String)?.hasPrefix("Zoomed") == true, "Pinching zooms in")

        viewer.swipeLeft()
        sleep(1)
        attachScreenshot(app, named: "Panned while zoomed")
        XCTAssertTrue(viewer.exists, "Dragging a zoomed photo pans it rather than closing")

        // A tap zooms back out; the next tap closes.
        viewer.tap()
        sleep(1)
        XCTAssertEqual(viewer.value as? String, "")
        viewer.doubleTap()
        sleep(1)
        attachScreenshot(app, named: "Double-tapped in")
        XCTAssertTrue((viewer.value as? String)?.hasPrefix("Zoomed") == true, "A double tap zooms in")
        viewer.doubleTap()
        sleep(1)
        viewer.tap()
        XCTAssertTrue(viewer.waitForNonExistence(timeout: 2), "A tap closes the photo when not zoomed")

        app.buttons["Edit Mosaic"].tap()
        let undo = app.buttons["Undo"]
        for _ in 0..<4 where undo.isEnabled {
            undo.tap()
        }
    }

    /// Needs a video in the simulator's library (`xcrun simctl addmedia`); skipped otherwise.
    @MainActor
    func testFadedShadowedVideoStillPlays() throws {
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

        let deadline = Date().addingTimeInterval(25)
        while app.images.count < 3, Date() < deadline { sleep(1) }
        sleep(1)
        attachScreenshot(app, named: "Picker")
        guard app.images.count >= 3 else {
            throw XCTSkip("No media in this simulator's library")
        }
        // The newest item, the added video, is the first cell (below the privacy banner when shown).
        let banner = app.staticTexts["Private Access to Photos"].exists
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.16, dy: banner ? 0.46 : 0.27)).tap()
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.905, dy: 0.153)).tap()
        sleep(10)
        attachScreenshot(app, named: "Video placed")

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.38)).press(forDuration: 0.8)
        let look = app.buttons["Opacity and shadow"]
        XCTAssertTrue(look.waitForExistence(timeout: 3))
        look.tap()
        app.buttons["Shadow Lifted"].tap()
        app.sliders.firstMatch.adjust(toNormalizedSliderPosition: 0.5)
        app.buttons["Frame Polaroid"].tap()
        let panelTop = app.sliders.firstMatch.frame.minY / app.frame.height
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: panelTop < 0.3 ? 0.44 : 0.34)).tap()
        XCTAssertTrue(app.sliders.firstMatch.waitForNonExistence(timeout: 2))

        // Selected now; the next tap plays it.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.36)).tap()
        sleep(1)
        attachScreenshot(app, named: "Faded video playing 1")
        sleep(1)
        attachScreenshot(app, named: "Faded video playing 2")

        let undo = app.buttons["Undo"]
        for _ in 0..<10 where undo.isEnabled {
            undo.tap()
        }
    }

    @MainActor
    func testTabStylesAndAccentColor() throws {
        let app = XCUIApplication()
        app.launchArguments += ["UITestSkipLaunchAnimation"]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["mosaic.screen"].waitForExistence(timeout: 5))
        app.buttons["Add to Mosaic"].tap()
        let search = app.textFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 2))
        search.tap()
        search.typeText("tabs")
        app.buttons["Tabs"].tap()
        // Near the top, so even this short board scrolls far enough for the bar to stick.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.2)).tap()
        let first = app.buttons["Tab 1"]
        XCTAssertTrue(first.waitForExistence(timeout: 3))
        sleep(1)
        attachScreenshot(app, named: "Tabs placed")

        first.press(forDuration: 0.8)
        let style = app.buttons["Tab style"]
        XCTAssertTrue(style.waitForExistence(timeout: 3))
        style.tap()
        let segmented = app.buttons["Tab style Segmented"]
        XCTAssertTrue(segmented.waitForExistence(timeout: 2))
        attachScreenshot(app, named: "Tab style panel")
        segmented.tap()
        attachScreenshot(app, named: "Segmented")
        // A color from the square, partway along the hues and in the saturated middle.
        let square = app.descendants(matching: .any)["composer.look.tabColor"]
        XCTAssertTrue(square.waitForExistence(timeout: 2))
        square.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.55)).tap()
        sleep(1)
        attachScreenshot(app, named: "Segmented with a picked color")
        app.buttons["Tab shape Rounded"].tap()
        sleep(1)
        attachScreenshot(app, named: "Segmented rounded")
        app.buttons["Tab width Full width"].tap()
        sleep(1)
        attachScreenshot(app, named: "Segmented rounded full width")
        app.buttons["Tab style Underline"].tap()
        sleep(1)
        attachScreenshot(app, named: "Underline full width")
        XCTAssertFalse(app.buttons["Tab shape Rounded"].exists, "Underline has no shape choice")
        app.buttons["Original tab color"].tap()
        app.buttons["Tab style Pill"].tap()
        sleep(1)
        attachScreenshot(app, named: "Pill rounded full width white")

        // Close the panel; switching tabs slides the mark across.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7)).tap()
        XCTAssertTrue(segmented.waitForNonExistence(timeout: 2))
        app.buttons["Tab 2"].tap()
        sleep(1)
        attachScreenshot(app, named: "Second tab open")
        XCTAssertTrue(app.buttons["Tab 2"].isSelected)

        // Pinned from the long-press menu, next to Lock. A hold on a selected tab bar moves it, so
        // tap off it first.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7)).tap()
        sleep(1)
        app.buttons["Tab 1"].press(forDuration: 0.8)
        let pin = app.buttons["Pin to top"]
        let pinShown = pin.waitForExistence(timeout: 3)
        attachScreenshot(app, named: "After long press for pin")
        XCTAssertTrue(pinShown)
        attachScreenshot(app, named: "Menu with pin")
        pin.tap()
        XCTAssertTrue(pin.waitForNonExistence(timeout: 2))

        // Scrolled far enough that the bar's own place is off screen, the sticky bar stays at the top,
        // under the status bar; scrolled back, it returns to its place. (The board's identifier hides
        // the bar's own, so the tab is found by its label.)
        let secondTab = app.buttons["Tab 2"]
        let placedY = secondTab.frame.minY
        let board = app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.75))
        board.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.2)))
        sleep(1)
        attachScreenshot(app, named: "Sticky tabs at the top")
        XCTAssertTrue(secondTab.exists && secondTab.isHittable, "The tab bar sticks at the top")
        XCTAssertGreaterThan(secondTab.frame.minY, 40, "Below the status bar")
        XCTAssertLessThan(secondTab.frame.minY, placedY, "Held at the top, above where it was placed")
        board.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.95)))
        sleep(1)
        attachScreenshot(app, named: "Tabs back in place")
        XCTAssertEqual(secondTab.frame.minY, placedY, accuracy: 4, "Back in its place once scrolled back")

        let undo = app.buttons["Undo"]
        for _ in 0..<8 where undo.isEnabled {
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
