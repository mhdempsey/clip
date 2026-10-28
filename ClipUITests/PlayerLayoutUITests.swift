import XCTest

@MainActor
final class PlayerLayoutUITests: XCTestCase {
    func testReaderSearchBrowsesWithoutSeekingUntilPlayFromHere() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-player-fixture", "--ui-test-reset-reader"]
        app.launch()
        let entry = app.buttons["player.reader"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        let scrubber = app.descendants(matching: .any)["player.scrubber"].firstMatch
        let original = scrubber.value as? String
        for _ in 0..<4 where !entry.isHittable { app.swipeUp(velocity: .fast) }
        entry.tap()
        app.buttons["reader.search"].tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("city")
        let result = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "reader.search.result.")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        keepScreenshot(of: app, named: "Search results within a book")
        result.tap()
        XCTAssertTrue(app.buttons["reader.play-from-here"].waitForExistence(timeout: 5))
        keepScreenshot(of: app, named: "Browsing a search match without moving audio")
        app.descendants(matching: .any)["reader.text"].firstMatch.swipeLeft()
        app.buttons["reader.show-controls"].tap()
        app.buttons["reader.done"].tap()
        XCTAssertEqual(scrubber.value as? String, original, "Search and subsequent browsing must leave audio untouched")
        for _ in 0..<4 where !entry.isHittable { app.swipeUp(velocity: .fast) }
        entry.tap()
        app.buttons["reader.search"].tap()
        field.tap()
        field.typeText("city")
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        result.tap()
        app.buttons["reader.play-from-here"].tap()
        expectation(for: NSPredicate(format: "label == %@", "Pause"), evaluatedWith: app.buttons["reader.play-pause"])
        waitForExpectations(timeout: 5)
        app.buttons["reader.play-pause"].tap()
        app.buttons["reader.done"].tap()
        XCTAssertNotEqual(scrubber.value as? String, original)
    }

    func testSavedClipsAreVisibleInReaderAndLibraryIncludingSentClips() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-player-fixture", "--ui-test-reset-reader", "--ui-test-saved-clips-fixture"]
        app.launch()
        let entry = app.buttons["player.reader"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        for _ in 0..<4 where !entry.isHittable { app.swipeUp(velocity: .fast) }
        entry.tap()
        app.buttons["reader.contents"].tap()
        app.segmentedControls["reader.book-tools"].buttons["Clips"].tap()
        let saved = app.buttons["book.clip.fixture-saved-clip"]
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["book.clip.fixture-sent-clip"].exists)
        keepScreenshot(of: app, named: "Saved and synced clips within a book")
        saved.tap()
        XCTAssertTrue(app.buttons["reader.play-from-here"].waitForExistence(timeout: 5))
        app.buttons["reader.done"].tap()
        XCTAssertEqual(app.descendants(matching: .any)["player.scrubber"].firstMatch.value as? String, "0:00 of 4:00")
        app.buttons["tab.library"].tap()
        app.buttons["library.actions.clip-ui-test-player"].tap()
        app.buttons["Clips & highlights"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["book.clip.fixture-saved-clip"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["book.clip.fixture-sent-clip"].firstMatch.exists)
        keepScreenshot(of: app, named: "Book clip history from the library")
    }

    func testReadAlongIsReachableAndOpensOnCompactPhone() {
        let app = XCUIApplication()
        app.launchArguments.append("--ui-test-player-fixture")
        app.launchArguments.append("--ui-test-reset-reader")
        app.launch()

        let player = app.descendants(matching: .any)["player.screen"]
        XCTAssertTrue(player.waitForExistence(timeout: 10))

        let readAlong = app.buttons["player.reader"]
        for _ in 0..<4 where !readAlong.isHittable {
            app.swipeUp(velocity: .fast)
        }

        XCTAssertTrue(readAlong.exists)
        XCTAssertTrue(readAlong.isHittable)
        XCTAssertTrue(app.descendants(matching: .any)["player.clip-payoff"].exists)
        keepScreenshot(of: app, named: "Player with reader entry")
        readAlong.tap()

        let reader = app.descendants(matching: .any)["reader.screen"]
        XCTAssertTrue(reader.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["reader.text"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["reader.play-pause"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.descendants(matching: .any)["reader.clip"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["reader.display"].isHittable)
        keepScreenshot(of: app, named: "Reader with chapter title")
    }

    func testReaderPagesAppearanceContentsAndSelection() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-player-fixture", "--ui-test-reset-reader"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["player.screen"].waitForExistence(timeout: 10))
        let readAlong = app.buttons["player.reader"]
        for _ in 0..<4 where !readAlong.isHittable { app.swipeUp(velocity: .fast) }
        XCTAssertTrue(readAlong.waitForExistence(timeout: 10))
        readAlong.tap()

        let text = app.descendants(matching: .any)["reader.text"].firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 10))
        let location = app.descendants(matching: .any)["reader.location"].firstMatch
        XCTAssertTrue(location.waitForExistence(timeout: 5))
        let pageReady = NSPredicate(format: "label CONTAINS %@", "Page 1 of")
        expectation(for: pageReady, evaluatedWith: location)
        waitForExpectations(timeout: 10)
        let firstPage = location.label
        XCTAssertTrue(firstPage.contains("Page 1 of"))
        text.swipeLeft()
        XCTAssertTrue(location.waitForExistence(timeout: 3))
        XCTAssertNotEqual(location.label, firstPage)
        XCTAssertTrue(app.buttons["reader.show-controls"].exists)
        keepScreenshot(of: app, named: "Reader quiet page")
        XCUIDevice.shared.orientation = .landscapeLeft
        expectation(for: NSPredicate { _, _ in text.frame.width > text.frame.height }, evaluatedWith: text)
        waitForExpectations(timeout: 5)
        let landscapePage = location.label
        text.swipeLeft()
        XCTAssertNotEqual(location.label, landscapePage)
        keepScreenshot(of: app, named: "Reader landscape page")
        XCUIDevice.shared.orientation = .portrait
        app.buttons["reader.show-controls"].tap()

        app.buttons["reader.display"].tap()
        XCTAssertTrue(app.buttons["reader.theme.sepia"].waitForExistence(timeout: 3))
        app.buttons["reader.theme.sepia"].tap()
        keepScreenshot(of: app, named: "Reader appearance controls")
        app.buttons["reader.appearance.done"].tap()
        keepScreenshot(of: app, named: "Reader sepia page")
        app.buttons["reader.display"].tap()
        app.buttons["reader.theme.dark"].tap()
        app.segmentedControls["reader.appearance.mode"].buttons["Scroll"].tap()
        app.buttons["reader.appearance.done"].tap()
        XCTAssertTrue(location.label.contains("% read"))
        keepScreenshot(of: app, named: "Reader dark continuous text")

        app.buttons["reader.contents"].tap()
        app.buttons["reader.chapter.1"].tap()
        XCTAssertTrue((text.value as? String)?.contains("Second Chapter") == true)
        text.swipeUp()
        XCTAssertTrue(app.buttons["reader.show-controls"].waitForExistence(timeout: 3))
        app.buttons["reader.show-controls"].tap()
        XCTAssertTrue(app.buttons["reader.resume"].isHittable)
    }

    func testNativeSelectionOffersHighlightAndPlayback() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-player-fixture", "--ui-test-reset-reader"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["player.screen"].waitForExistence(timeout: 10))
        let readAlong = app.buttons["player.reader"]
        for _ in 0..<4 where !readAlong.isHittable { app.swipeUp(velocity: .fast) }
        readAlong.tap()
        let text = app.descendants(matching: .any)["reader.text"].firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 10))
        let pageReady = NSPredicate(format: "label CONTAINS %@", "Page 1 of")
        expectation(for: pageReady, evaluatedWith: app.descendants(matching: .any)["reader.location"].firstMatch)
        waitForExpectations(timeout: 10)
        let openingParagraph = text.descendants(matching: .textView)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "The morning light")).firstMatch
        XCTAssertTrue(openingParagraph.waitForExistence(timeout: 3))
        openingParagraph.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.08)).press(forDuration: 1)
        XCTAssertTrue(app.menuItems["Highlight"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.menuItems["Play from here"].exists)
        keepScreenshot(of: app, named: "Reader native selection actions")
    }

    func testReaderPageAndChapterNavigationSeekAudioWhileKeepingItPaused() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-player-fixture", "--ui-test-reset-reader"]
        app.launch()
        let entry = app.buttons["player.reader"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        for _ in 0..<4 where !entry.isHittable { app.swipeUp(velocity: .fast) }
        entry.tap()
        let location = app.descendants(matching: .any)["reader.location"].firstMatch
        expectation(for: NSPredicate(format: "label CONTAINS %@", "Page 1 of"), evaluatedWith: location)
        waitForExpectations(timeout: 10)
        app.descendants(matching: .any)["reader.text"].firstMatch.swipeLeft()
        app.buttons["reader.show-controls"].tap()
        XCTAssertTrue(app.buttons["reader.resume"].label.contains("Following audio"))
        XCTAssertEqual(app.buttons["reader.play-pause"].label, "Play")
        keepScreenshot(of: app, named: "Paused audio follows page turn with highlight")
        app.buttons["reader.done"].tap()
        let scrubber = app.descendants(matching: .any)["player.scrubber"].firstMatch
        XCTAssertTrue(scrubber.waitForExistence(timeout: 5))
        XCTAssertNotEqual(scrubber.value as? String, "0:00 of 4:00")
        for _ in 0..<4 where !entry.isHittable { app.swipeUp(velocity: .fast) }
        entry.tap()
        app.buttons["reader.contents"].tap()
        app.buttons["reader.chapter.1"].tap()
        XCTAssertEqual(app.buttons["reader.play-pause"].label, "Play")
        app.buttons["reader.done"].tap()
        XCTAssertEqual(scrubber.value as? String, "2:00 of 4:00")
    }

    func testCompactLibrarySortArchiveAndRestore() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-player-fixture", "--ui-test-library-fixture", "--ui-test-reset-reader"]
        app.launch()
        let layout = app.buttons["library.layout"]
        XCTAssertTrue(layout.waitForExistence(timeout: 10))
        XCTAssertTrue(layout.label.contains("Compact list"))
        keepScreenshot(of: app, named: "Compact library with small covers")
        app.buttons["library.sort"].tap()
        app.buttons["Title"].tap()
        XCTAssertTrue(app.buttons["library.sort"].label.contains("Title"))
        let book = app.buttons["library.book.library-fixture-0"]
        XCTAssertTrue(book.isHittable)
        app.buttons["library.actions.library-fixture-0"].tap()
        app.buttons["Mark as Read"].tap()
        XCTAssertFalse(book.exists)
        app.segmentedControls["library.filter"].buttons["Read"].tap()
        XCTAssertTrue(book.waitForExistence(timeout: 3))
        keepScreenshot(of: app, named: "Archived read books")
        app.buttons["library.actions.library-fixture-0"].tap()
        app.buttons["Move to Reading"].tap()
        XCTAssertFalse(book.exists)
        app.segmentedControls["library.filter"].buttons["Reading"].tap()
        XCTAssertTrue(book.waitForExistence(timeout: 3))
        layout.tap()
        app.buttons["Cover grid"].tap()
        XCTAssertTrue(layout.label.contains("Cover grid"))
        layout.tap()
        app.buttons["Compact list"].tap()
        XCTAssertTrue(layout.label.contains("Compact list"))
        app.terminate()
        app.launchArguments.removeAll { $0 == "--ui-test-reset-reader" }
        app.launch()
        XCTAssertTrue(layout.waitForExistence(timeout: 10))
        XCTAssertTrue(layout.label.contains("Compact list"))
        XCTAssertTrue(app.buttons["library.sort"].label.contains("Title"))
    }

    private func keepScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
