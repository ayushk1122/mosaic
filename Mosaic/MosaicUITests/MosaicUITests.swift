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
    func testHomeOpensGolfOverview() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["home.screen"].waitForExistence(timeout: 5))
        let golf = app.buttons["pursuit.golf.open"]
        XCTAssertTrue(golf.exists)
        XCTAssertTrue(golf.label.contains("Building a more confident, consistent game"))
        XCTAssertTrue(golf.label.contains("Open journey"))

        for pursuit in ["fitness", "modeling", "cooking"] {
            XCTAssertTrue(app.descendants(matching: .any)["pursuit.\(pursuit).planned"].exists)
            XCTAssertFalse(app.buttons["pursuit.\(pursuit).planned"].exists)
        }

        attachScreenshot(named: "Home", from: app)
        golf.tap()
        XCTAssertTrue(app.descendants(matching: .any)["golf.overview"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Add"].exists)
        XCTAssertFalse(app.buttons["Edit"].exists)
        XCTAssertFalse(app.buttons["Save"].exists)

        let seasonMosaic = app.descendants(matching: .any)["golf.season-mosaic"]
        for _ in 0..<10 where !seasonMosaic.exists {
            app.swipeUp()
        }
        XCTAssertTrue(seasonMosaic.exists)
        attachScreenshot(named: "Golf", from: app)
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

    private func attachScreenshot(named name: String, from app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
