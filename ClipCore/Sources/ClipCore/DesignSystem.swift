#if canImport(SwiftUI)
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public enum ClipDesign {
    public static let cardRadius: CGFloat = 8
    public static let controlRadius: CGFloat = 6
    public static let hairlineWidth: CGFloat = 1
    public static let pageMargin: CGFloat = 24

    public static let paper = adaptiveColor(light: 0xF7F2E6, dark: 0x15110B)
    public static let surface = adaptiveColor(light: 0xFCF8EF, dark: 0x1E1912)
    public static let ink = adaptiveColor(light: 0x1E1A13, dark: 0xEDE5D3)
    public static let inkSecondary = adaptiveColor(light: 0x6E6455, dark: 0xA79B85)
    public static let hairline = adaptiveColor(light: 0xD9CFBB, dark: 0x342D21)
    public static let terracotta = adaptiveColor(light: 0xC2542B, dark: 0xCE6B43)
    public static let terracottaPressed = adaptiveColor(light: 0xA64621, dark: 0xB5552F)

    public static func bodyFont(size: CGFloat = 17, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom("EBGaramond-Regular", size: size, relativeTo: style)
    }

    public static func mediumFont(size: CGFloat = 17, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom("EBGaramond-Medium", size: size, relativeTo: style)
    }

    public static func semiboldFont(size: CGFloat = 17, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom("EBGaramond-SemiBold", size: size, relativeTo: style)
    }

    public static func italicFont(size: CGFloat = 17, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom("EBGaramond-Italic", size: size, relativeTo: style)
    }

    public static func readerFont(size: CGFloat = 20) -> Font { bodyFont(size: size, relativeTo: .body) }
    public static func timeFont(size: CGFloat = 15) -> Font { .system(size: size, weight: .regular, design: .monospaced) }

    private static func adaptiveColor(light: UInt32, dark: UInt32) -> Color {
        #if canImport(UIKit)
        Color(UIColor { traits in UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light) })
        #elseif canImport(AppKit)
        Color(NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.darkAqua, .aqua])
            return NSColor(rgb: match == .darkAqua ? dark : light)
        })
        #else
        Color(red: Double((light >> 16) & 0xFF) / 255, green: Double((light >> 8) & 0xFF) / 255, blue: Double(light & 0xFF) / 255)
        #endif
    }
}

public struct StampChipStyle: ButtonStyle {
    public var isSelected: Bool

    public init(isSelected: Bool) {
        self.isSelected = isSelected
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(ClipDesign.mediumFont(size: 14))
            .textCase(.uppercase)
            .tracking(0.7)
            .foregroundStyle(isSelected ? ClipDesign.paper : ClipDesign.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: ClipDesign.controlRadius)
                    .fill(isSelected ? (configuration.isPressed ? ClipDesign.terracottaPressed : ClipDesign.terracotta) : ClipDesign.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: ClipDesign.controlRadius)
                    .stroke(isSelected ? ClipDesign.terracotta : ClipDesign.hairline, lineWidth: ClipDesign.hairlineWidth)
            )
            .opacity(configuration.isPressed && !isSelected ? 0.72 : 1)
    }
}

public struct PrimaryClipButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(ClipDesign.semiboldFont(size: 16))
            .textCase(.uppercase)
            .tracking(0.8)
            .foregroundStyle(ClipDesign.paper)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: ClipDesign.controlRadius)
                    .fill(configuration.isPressed ? ClipDesign.terracottaPressed : ClipDesign.terracotta)
            )
    }
}

public struct PaperCardModifier: ViewModifier {
    public init() {}

    public func body(content: Content) -> some View {
        content
            .padding(16)
            .background(ClipDesign.surface)
            .clipShape(RoundedRectangle(cornerRadius: ClipDesign.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: ClipDesign.cardRadius)
                    .stroke(ClipDesign.hairline, lineWidth: ClipDesign.hairlineWidth)
            )
    }
}

public struct StampFrame: ViewModifier {
    public var caption: String?

    public init(caption: String? = nil) {
        self.caption = caption
    }

    public func body(content: Content) -> some View {
        VStack(spacing: 7) {
            content
                .padding(7)
                .background(ClipDesign.surface)
                .overlay(StampPerforatedBorder().stroke(ClipDesign.hairline, lineWidth: ClipDesign.hairlineWidth))
            if let caption, !caption.isEmpty {
                Text(caption)
                    .font(ClipDesign.mediumFont(size: 12))
                    .textCase(.uppercase)
                    .tracking(0.8)
                    .foregroundStyle(ClipDesign.inkSecondary)
                    .lineLimit(1)
            }
        }
    }
}

public struct StampPerforatedBorder: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRoundedRect(in: rect.insetBy(dx: 0.5, dy: 0.5), cornerSize: CGSize(width: 2, height: 2))
        let pitch: CGFloat = 6
        let radius: CGFloat = 1.5
        var x = rect.minX + pitch / 2
        while x < rect.maxX {
            path.addEllipse(in: CGRect(x: x - radius, y: rect.minY - radius, width: radius * 2, height: radius * 2))
            path.addEllipse(in: CGRect(x: x - radius, y: rect.maxY - radius, width: radius * 2, height: radius * 2))
            x += pitch
        }
        var y = rect.minY + pitch / 2
        while y < rect.maxY {
            path.addEllipse(in: CGRect(x: rect.minX - radius, y: y - radius, width: radius * 2, height: radius * 2))
            path.addEllipse(in: CGRect(x: rect.maxX - radius, y: y - radius, width: radius * 2, height: radius * 2))
            y += pitch
        }
        return path
    }
}

public extension View {
    func paperCard() -> some View { modifier(PaperCardModifier()) }
    func stampFrame(caption: String? = nil) -> some View { modifier(StampFrame(caption: caption)) }
    func clipSmallCaps() -> some View { textCase(.uppercase).tracking(0.8) }
}

#if canImport(UIKit)
private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
#elseif canImport(AppKit)
private extension NSColor {
    convenience init(rgb: UInt32) {
        self.init(
            calibratedRed: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
#endif
#endif
