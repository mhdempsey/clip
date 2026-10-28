import XCTest

@MainActor
final class AppStoreScreenshotUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += [
            "-ApplePersistenceIgnoreState", "YES",
            "-ClipMac.HasSeenOnboarding", "YES",
            "-Clip.AlignmentLocation", "onMac",
            "--ui-test-pairing-fixture",
        ]
        app.launch()
    }

    func testCaptureMacAppStoreScreenshots() {
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 15))

        let pairingCard = app.descendants(matching: .any)["pairing-card"]
        XCTAssertTrue(pairingCard.waitForExistence(timeout: 10))
        keepScreenshot(of: window, named: "02-pairing-ready")

        let shelfButton = app.buttons["section-shelf"]
        XCTAssertTrue(shelfButton.waitForExistence(timeout: 5))
        shelfButton.click()
        XCTAssertTrue(app.descendants(matching: .any)["finished-books-shelf"].waitForExistence(timeout: 5))
        keepScreenshot(of: window, named: "03-shelf")

        app.typeKey(",", modifierFlags: .command)
        let qualityButton = app.buttons["quality-standard"]
        XCTAssertTrue(qualityButton.waitForExistence(timeout: 5))
        let settingsWindow = app.windows.containing(.button, identifier: "quality-standard").element
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 5))
        keepScreenshot(of: settingsWindow, named: "04-settings")
    }

    private func keepScreenshot(of element: XCUIElement, named name: String) {
        let attachment = XCTAttachment(screenshot: element.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
