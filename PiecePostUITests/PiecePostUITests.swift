//
//  PiecePostUITests.swift
//  PiecePostUITests
//
//  Created by JinHyoung Kim on 10/31/26.
//

import XCTest

final class PiecePostUITests: XCTestCase {

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
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        // UI 테스트 중에는 CloudKit 동기화를 켜지 않는다.
        app.launchArguments = ["-PiecePostDisableSync"]
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
        // XCUIAutomation Documentation
        // https://developer.apple.com/documentation/xcuiautomation
    }

    /// 동기화를 끈 실행(엔진 없음)에서도 두 버튼이 보이고, 앱이 멈추지 않는다.
    @MainActor
    func testSyncButtonsWithoutEngine() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-PiecePostDisableSync"]
        app.launch()

        let fetch = app.buttons["지금 가져오기"]
        let send = app.buttons["지금 보내기"]
        XCTAssertTrue(fetch.waitForExistence(timeout: 5))
        XCTAssertTrue(send.exists)
        // 엔진이 없으면 연결 전 상태라 눌러도 아무 일이 없다.
        XCTAssertFalse(send.isEnabled)
        send.tap()
        XCTAssertTrue(app.navigationBars["동기화 시험"].exists)
    }

    /// 시험 화면 → 톱니 → 설정 화면(동기화 끈 실행이라 "확인하는 중") → 닫기로 돌아온다.
    @MainActor
    func testSettingsOpensAndCloses() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-PiecePostDisableSync"]
        app.launch()

        let gear = app.buttons["설정"]
        XCTAssertTrue(gear.waitForExistence(timeout: 5))
        gear.tap()

        XCTAssertTrue(app.navigationBars["설정"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["iCloud 백업"].exists)
        XCTAssertTrue(app.staticTexts["정보"].exists)
        XCTAssertTrue(app.staticTexts["버전"].exists)
        let statusTitle = app.staticTexts["syncStatusTitle"]
        XCTAssertTrue(statusTitle.exists)
        XCTAssertEqual(statusTitle.label, "확인하는 중")

        app.buttons["닫기"].tap()
        XCTAssertTrue(app.navigationBars["동기화 시험"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["설정"].exists)
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            let app = XCUIApplication()
            app.launchArguments = ["-PiecePostDisableSync"]
            app.launch()
        }
    }
}
