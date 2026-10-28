import Foundation

struct ReaderAppearance: Codable, Equatable {
    enum Mode: String, Codable, CaseIterable { case pages, scroll }
    enum Theme: String, Codable, CaseIterable { case white, sepia, dark }
    enum Typeface: String, Codable, CaseIterable {
        case garamond, georgia, palatino, sans
        var title: String {
            switch self {
            case .garamond: "Garamond"
            case .georgia: "Georgia"
            case .palatino: "Palatino"
            case .sans: "Sans serif"
            }
        }
    }

    var mode: Mode = .pages
    var theme: Theme = .white
    var typeface: Typeface = .garamond
    var textSize = 22.0
    var lineSpacing = 5.0
    var margin = 24.0
    var justified = false

    var validated: Self {
        var result = self
        result.textSize = textSize.isFinite ? min(max(textSize, 14), 40) : 22
        result.lineSpacing = lineSpacing.isFinite ? min(max(lineSpacing, 0), 18) : 5
        result.margin = margin.isFinite ? min(max(margin, 16), 48) : 24
        return result
    }
}

@MainActor
final class ReaderPreferences: ObservableObject {
    private let defaults: UserDefaults
    private static let key = "Clip.Reader.Appearance.v1"
    @Published var value: ReaderAppearance {
        didSet {
            if value != value.validated { value = value.validated }
            if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: Self.key) }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode(ReaderAppearance.self, from: data) {
            value = saved.validated
        } else {
            var migrated = ReaderAppearance()
            if defaults.object(forKey: "Clip.Reader.TextSize") != nil {
                migrated.textSize = defaults.double(forKey: "Clip.Reader.TextSize")
            }
            if defaults.object(forKey: "Clip.Reader.LineSpacing") != nil {
                migrated.lineSpacing = defaults.double(forKey: "Clip.Reader.LineSpacing")
            }
            value = migrated.validated
            if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: Self.key) }
        }
    }

    func reset() { value = ReaderAppearance() }
}
