import XCTest
@testable import Clip

@MainActor
final class ReaderPreferencesTests: XCTestCase {
    func testPreferencesMigratePersistAndResetTogether() throws {
        let name = "ReaderPreferencesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(27.0, forKey: "Clip.Reader.TextSize")
        defaults.set(12.0, forKey: "Clip.Reader.LineSpacing")
        let preferences = ReaderPreferences(defaults: defaults)
        XCTAssertEqual(preferences.value.textSize, 27)
        XCTAssertEqual(preferences.value.mode, .pages)
        preferences.value.theme = .dark
        preferences.value.mode = .scroll
        preferences.value.typeface = .georgia
        preferences.value.margin = 38
        let restored = ReaderPreferences(defaults: defaults)
        XCTAssertEqual(restored.value, preferences.value)
        restored.reset()
        XCTAssertEqual(restored.value, ReaderAppearance())
        XCTAssertEqual(ReaderPreferences(defaults: defaults).value, ReaderAppearance())
    }

    func testInvalidValuesAreClampedBeforeLayout() {
        var appearance = ReaderAppearance()
        appearance.textSize = .infinity
        appearance.lineSpacing = -100
        appearance.margin = 999
        let validated = appearance.validated
        XCTAssertEqual(validated.textSize, 22)
        XCTAssertEqual(validated.lineSpacing, 0)
        XCTAssertEqual(validated.margin, 48)
    }
}
