import XCTest

@MainActor
final class PlayerLayoutUITests: XCTestCase {
    func testReadAlongIsReachableAndOpensOnCompactPhone() {
        let app = XCUIApplication()
        app.launchArguments.append("--ui-test-player-fixture")
        app.launch()

        let player = app.descendants(matching: .any)["player.screen"]
        XCTAssertTrue(player.waitForExistence(timeout: 10))

        let readAlong = app.buttons["player.reader"]
        for _ in 0..<4 where !readAlong.isHittable {
            app.swipeUp(velocity: .fast)
        }

        XCTAssertTrue(readAlong.exists)
        XCTAssertTrue(readAlong.isHittable)
        keepScreenshot(of: app, named: "Player bottom on iPhone 13 Pro")
        readAlong.tap()

        let reader = app.descendants(matching: .any)["reader.screen"]
        XCTAssertTrue(reader.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["OPENING"].exists)
        keepScreenshot(of: app, named: "Reader with chapter title")
    }

    private func keepScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
