//
//  PiecePostUITestsLaunchTests.swift
//  PiecePostUITests
//
//  Created by JinHyoung Kim on 10/31/26.
//

import XCTest

final class PiecePostUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        // UI 테스트 중에는 CloudKit 동기화를 켜지 않는다.
        app.launchArguments = ["-PiecePostDisableSync"]
        app.launch()

        // Insert steps here to perform after app launch but before taking a screenshot,
        // such as logging into a test account or navigating somewhere in the app
        // XCUIAutomation Documentation
        // https://developer.apple.com/documentation/xcuiautomation

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
