import ClipCore
import SwiftUI
import UIKit

enum ClipTypography {
    static func body(_ size: CGFloat = 17) -> Font { ClipDesign.bodyFont(size: size) }
    static func title(_ size: CGFloat = 28) -> Font { ClipDesign.mediumFont(size: size, relativeTo: .title2) }
    static func semibold(_ size: CGFloat = 17) -> Font { ClipDesign.semiboldFont(size: size) }
    static func italic(_ size: CGFloat = 17) -> Font { ClipDesign.italicFont(size: size) }
    static func time(_ size: CGFloat = 15) -> Font { .system(size: size, design: .rounded).monospacedDigit() }
}

struct ClipScreenTitle: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(ClipDesign.mediumFont(size: 42, relativeTo: .largeTitle))
            .foregroundStyle(ClipDesign.ink)
            .accessibilityAddTraits(.isHeader)
    }
}

struct SmallCapsLabel: View {
    let text: String
    var color = ClipDesign.inkSecondary

    var body: some View {
        Text(text.uppercased())
            .font(ClipTypography.semibold(12))
            .tracking(1.2)
            .foregroundStyle(color)
    }
}

struct DurationStampPicker: View {
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(ClipShared.supportedClipWindowSeconds, id: \.self) { duration in
                Button {
                    selection = duration
                } label: {
                    Text("\(duration)s")
                        .font(ClipTypography.semibold(15))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .foregroundStyle(selection == duration ? ClipDesign.paper : ClipDesign.ink)
                        .background(selection == duration ? ClipDesign.terracotta : ClipDesign.surface)
                        .clipShape(RoundedRectangle(cornerRadius: ClipDesign.controlRadius))
                        .overlay {
                            RoundedRectangle(cornerRadius: ClipDesign.controlRadius)
                                .stroke(selection == duration ? ClipDesign.terracotta : ClipDesign.hairline, lineWidth: ClipDesign.hairlineWidth)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(duration) seconds")
                .accessibilityAddTraits(selection == duration ? .isSelected : [])
                .accessibilityIdentifier("clip.duration.\(duration)")
            }
        }
    }
}

struct ClipPrimaryButton: View {
    let title: String
    let systemImage: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(ClipTypography.semibold(18))
                .tracking(0.3)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(ClipDesign.paper)
                .background(ClipDesign.terracotta)
                .clipShape(RoundedRectangle(cornerRadius: ClipDesign.controlRadius))
        }
        .buttonStyle(.plain)
    }
}

struct StampCover: View {
    let book: BookRecord
    var width: CGFloat = 130
    var caption = true

    var body: some View {
        VStack(spacing: 8) {
            Group {
                if let url = book.coverURL, let image = CoverImageCache.image(at: url) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        ClipDesign.surface
                        Image(systemName: "book.closed")
                            .font(.system(size: width * 0.26, weight: .light))
                            .foregroundStyle(ClipDesign.inkSecondary)
                    }
                }
            }
            .frame(width: width, height: width * 1.48)
            .clipped()
            .padding(5)
            .background(ClipDesign.surface)
            .overlay { Rectangle().stroke(ClipDesign.hairline, lineWidth: ClipDesign.hairlineWidth) }
            .overlay { PerforatedEdge().stroke(ClipDesign.paper, style: StrokeStyle(lineWidth: 4, dash: [1, 5])) }

            if caption {
                Text(book.title.uppercased())
                    .font(ClipTypography.semibold(10))
                    .tracking(0.8)
                    .foregroundStyle(ClipDesign.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: width)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(book.title), by \(book.author)")
    }
}

private struct PerforatedEdge: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect.insetBy(dx: 2, dy: 2))
        return path
    }
}

struct ClipToast: View {
    let message: String

    var body: some View {
        Text(message)
            .font(ClipTypography.italic(18))
            .foregroundStyle(ClipDesign.paper)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(ClipDesign.ink)
            .clipShape(RoundedRectangle(cornerRadius: ClipDesign.controlRadius))
            .accessibilityIdentifier("clip.toast")
    }
}

@MainActor
private enum CoverImageCache {
    private static let cache = NSCache<NSString, UIImage>()

    static func image(at url: URL) -> UIImage? {
        let key = url.path as NSString
        if let image = cache.object(forKey: key) { return image }
        guard let image = UIImage(contentsOfFile: url.path) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }
}
