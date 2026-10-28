import XCTest

@MainActor
final class OpenRouterSettingsUITests: XCTestCase {
    func testCloudSettingsAndLocalQualityControls() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-ApplePersistenceIgnoreState", "YES",
            "-ClipMac.HasSeenOnboarding", "YES",
            "-Clip.AlignmentLocation", "openRouter"
        ]
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))
        app.typeKey(",", modifierFlags: .command)
        let key = app.secureTextFields["openrouter-api-key"]
        XCTAssertTrue(key.waitForExistence(timeout: 10))
        XCTAssertTrue(app.textFields["openrouter-spending-limit"].exists)
        XCTAssertFalse(app.buttons["openrouter-save-key"].isEnabled)
        let screenshot = XCTAttachment(screenshot: app.windows.containing(.secureTextField, identifier: "openrouter-api-key").element.screenshot())
        screenshot.name = "OpenRouter settings"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.radioButtons["On this Mac"].click()
        XCTAssertTrue(app.buttons["quality-standard"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["quality-maximum"].exists)
    }
}
