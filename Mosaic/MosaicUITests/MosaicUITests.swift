//
//  MosaicUITests.swift
//  MosaicUITests
//
//  Created by Ayush Krishnappa on 9/28/26.
//

import XCTest

final class MosaicUITests: XCTestCase {
    @MainActor
    func testHomeOpensGolfOverview() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["home.screen"].waitForExistence(timeout: 5))
        let golf = app.buttons["pursuit.golf.open"]
        XCTAssertTrue(golf.waitForExistence(timeout: 5))
        golf.tap()
        XCTAssertTrue(app.descendants(matching: .any)["golf.overview"].waitForExistence(timeout: 5))
    }
}
