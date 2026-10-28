import SwiftUI
import UIKit

struct ReaderPalette {
    let paper: UIColor
    let ink: UIColor
    let secondary: UIColor
    let accent: UIColor
    let spoken: UIColor

    init(theme: ReaderAppearance.Theme) {
        switch theme {
        case .white:
            paper = UIColor(readerHex: 0xFFFFFF)
            ink = UIColor(readerHex: 0x252525)
            secondary = UIColor(readerHex: 0x686868)
            accent = UIColor(readerHex: 0x234F76)
            spoken = UIColor(readerHex: 0xE9EFF3)
        case .sepia:
            paper = UIColor(readerHex: 0xF5EDDC)
            ink = UIColor(readerHex: 0x3D3429)
            secondary = UIColor(readerHex: 0x766651)
            accent = UIColor(readerHex: 0x725334)
            spoken = UIColor(readerHex: 0xE8DCC5)
        case .dark:
            paper = UIColor(readerHex: 0x171919)
            ink = UIColor(readerHex: 0xDDDCD5)
            secondary = UIColor(readerHex: 0xA2A49E)
            accent = UIColor(readerHex: 0xB8CDD8)
            spoken = UIColor(readerHex: 0x303B3E)
        }
    }
}

extension ReaderAppearance {
    var palette: ReaderPalette { ReaderPalette(theme: theme) }

    func font(compatibleWith traits: UITraitCollection) -> UIFont {
        let base: UIFont
        switch typeface {
        case .garamond: base = UIFont(name: "EBGaramond-Regular", size: textSize) ?? .systemFont(ofSize: textSize)
        case .georgia: base = UIFont(name: "Georgia", size: textSize) ?? .systemFont(ofSize: textSize)
        case .palatino: base = UIFont(name: "Palatino-Roman", size: textSize) ?? .systemFont(ofSize: textSize)
        case .sans: base = .systemFont(ofSize: textSize)
        }
        return UIFontMetrics(forTextStyle: .body).scaledFont(for: base, compatibleWith: traits)
    }
}

struct ReaderAppearanceSheet: View {
    @ObservedObject var preferences: ReaderPreferences
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Reading mode", selection: $preferences.value.mode) {
                        Text("Pages").tag(ReaderAppearance.Mode.pages)
                        Text("Scroll").tag(ReaderAppearance.Mode.scroll)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("reader.appearance.mode")
                    HStack(spacing: 12) {
                        ForEach(ReaderAppearance.Theme.allCases, id: \.self) { theme in
                            themeButton(theme)
                        }
                    }
                    .listRowSeparator(.hidden)
                }

                Section("Typography") {
                    Picker("Font", selection: $preferences.value.typeface) {
                        ForEach(ReaderAppearance.Typeface.allCases, id: \.self) { font in
                            Text(font.title).tag(font)
                        }
                    }
                    .accessibilityIdentifier("reader.appearance.font")
                    Stepper(value: $preferences.value.textSize, in: 14...40, step: 1) {
                        HStack {
                            Text("Text size")
                            Spacer()
                            Text("\(Int(preferences.value.textSize))").monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("reader.appearance.size")
                    adjustment("Line spacing", value: $preferences.value.lineSpacing, range: 0...18)
                    adjustment("Margins", value: $preferences.value.margin, range: 16...48)
                    Toggle("Justified text", isOn: $preferences.value.justified)
                        .accessibilityIdentifier("reader.appearance.justified")
                }

                Section {
                    Text("The best part of a book is finding a sentence that seems to have been waiting for you.")
                        .font(Font(preferences.value.font(compatibleWith: .current)))
                        .lineSpacing(preferences.value.lineSpacing)
                        .foregroundStyle(Color(preferences.value.palette.ink))
                        .padding(.horizontal, preferences.value.margin - 16)
                        .padding(.vertical, 18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .listRowBackground(Color(preferences.value.palette.paper))
                        .accessibilityIdentifier("reader.appearance.preview")
                } header: { Text("Preview") } footer: { Text("Your reading preferences apply to every book.") }

                Section {
                    Button("Reset reading display") { preferences.reset() }
                        .accessibilityIdentifier("reader.appearance.reset")
                }
            }
            .navigationTitle("Reading appearance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("reader.appearance.done")
                }
            }
        }
        .tint(Color(preferences.value.palette.accent))
        .preferredColorScheme(preferences.value.theme == .dark ? .dark : .light)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func themeButton(_ theme: ReaderAppearance.Theme) -> some View {
        let selected = preferences.value.theme == theme
        let palette = ReaderPalette(theme: theme)
        return Button { preferences.value.theme = theme } label: {
            VStack(spacing: 6) {
                Text("Aa").font(.system(size: 23, design: .serif))
                Text(theme == .white ? "White" : theme == .sepia ? "Sepia" : "Dark").font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(Color(palette.ink))
            .frame(maxWidth: .infinity, minHeight: 76)
            .background(Color(palette.paper), in: RoundedRectangle(cornerRadius: 10))
            .overlay { RoundedRectangle(cornerRadius: 10).stroke(selected ? Color(palette.accent) : Color.gray.opacity(0.25), lineWidth: selected ? 2 : 1) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(theme.rawValue.capitalized) theme")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("reader.theme.\(theme.rawValue)")
    }

    private func adjustment(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(value.wrappedValue))").foregroundStyle(.secondary).monospacedDigit()
            }
            Slider(value: value, in: range, step: 1)
                .accessibilityLabel(title)
                .accessibilityIdentifier("reader.appearance.\(title == "Margins" ? "margins" : "spacing")")
        }
    }
}

private extension UIColor {
    convenience init(readerHex value: UInt32) {
        self.init(red: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: 1)
    }
}
