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

        XCTAssertTrue(app.scrollViews["home.screen"].waitForExistence(timeout: 5))
        let golf = app.buttons["pursuit.golf.open"]
        XCTAssertTrue(golf.exists)
        golf.tap()
        XCTAssertTrue(app.scrollViews["golf.overview"].waitForExistence(timeout: 5))
    }
}
