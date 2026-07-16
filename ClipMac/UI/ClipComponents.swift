import AppKit
import ClipCore
import SwiftUI
import UniformTypeIdentifiers

enum ClipFont {
    static func regular(_ size: CGFloat) -> Font { .custom("EB Garamond", size: size) }
    static func medium(_ size: CGFloat) -> Font { .custom("EB Garamond Medium", size: size) }
    static func semibold(_ size: CGFloat) -> Font { .custom("EB Garamond SemiBold", size: size) }
    static func italic(_ size: CGFloat) -> Font { .custom("EB Garamond", size: size).italic() }
}

struct SmallCapsLabel: View {
    let text: String
    var color: Color = ClipDesign.inkSecondary

    var body: some View {
        Text(text.uppercased())
            .font(ClipDesign.labelFont(size: 11))
            .tracking(1.25)
            .foregroundStyle(color)
    }
}

struct Fleuron: View {
    var body: some View {
        Text("❦")
            .font(ClipFont.regular(24))
            .foregroundStyle(ClipDesign.marigold)
            .accessibilityHidden(true)
    }
}

struct PerforatedStampShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        let diameter: CGFloat = 3
        let pitch: CGFloat = 6

        var x = rect.minX + pitch
        while x < rect.maxX {
            path.addEllipse(in: CGRect(x: x - diameter / 2, y: rect.minY - diameter / 2, width: diameter, height: diameter))
            path.addEllipse(in: CGRect(x: x - diameter / 2, y: rect.maxY - diameter / 2, width: diameter, height: diameter))
            x += pitch
        }
        var y = rect.minY + pitch
        while y < rect.maxY {
            path.addEllipse(in: CGRect(x: rect.minX - diameter / 2, y: y - diameter / 2, width: diameter, height: diameter))
            path.addEllipse(in: CGRect(x: rect.maxX - diameter / 2, y: y - diameter / 2, width: diameter, height: diameter))
            y += pitch
        }
        return path
    }
}

struct StampCover: View {
    var data: Data?
    var url: URL?
    var caption: String?
    var width: CGFloat = 124

    private var image: NSImage? {
        if let data, let image = NSImage(data: data) { return image }
        if let url { return NSImage(contentsOf: url) }
        return nil
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                ClipDesign.surface
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    VStack(spacing: 9) {
                        Fleuron()
                        Image(systemName: "book.closed")
                            .font(.system(size: width * 0.22, weight: .thin))
                            .foregroundStyle(ClipDesign.ink)
                    }
                }
            }
            .frame(width: width, height: width * 1.48)
            .clipped()
            .padding(7)
            .background(ClipDesign.surface)
            .overlay {
                Rectangle().stroke(ClipDesign.hairline, lineWidth: ClipDesign.hairlineWidth)
            }
            .mask {
                PerforatedStampShape().fill(style: FillStyle(eoFill: true))
            }
            .shadow(color: ClipDesign.shadow, radius: 10, y: 6)

            if let caption {
                SmallCapsLabel(text: caption)
                    .lineLimit(1)
                    .frame(maxWidth: width + 8)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(caption.map { "Cover of \($0)" } ?? "Book cover")
    }
}

struct ClipProgressBar: View {
    let value: Double
    var active = true

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(ClipDesign.ink.opacity(0.16))
                Capsule()
                    .fill(active ? ClipDesign.terracotta : ClipDesign.ink)
                    .frame(width: proxy.size.width * min(1, max(0, value)))
            }
        }
        .frame(height: 5)
        .accessibilityValue("\(Int(value * 100)) percent")
    }
}

struct PaperButtonStyle: ButtonStyle {
    enum Role { case primary, secondary, quiet }
    let role: Role

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(ClipDesign.labelFont(size: 13, weight: .medium))
            .foregroundStyle(foreground(configuration))
            .padding(.horizontal, role == .quiet ? 7 : 15)
            .padding(.vertical, role == .quiet ? 5 : 9)
            .background(background(configuration))
            .clipShape(RoundedRectangle(cornerRadius: ClipDesign.controlRadius))
            .overlay {
                if role == .secondary {
                    RoundedRectangle(cornerRadius: ClipDesign.controlRadius)
                        .stroke(ClipDesign.hairlineStrong, lineWidth: ClipDesign.hairlineWidth)
                }
            }
            .contentShape(Rectangle())
    }

    private func foreground(_ configuration: Configuration) -> Color {
        switch role {
        case .primary: ClipDesign.paper
        case .secondary, .quiet: configuration.isPressed ? ClipDesign.inkSecondary : ClipDesign.ink
        }
    }

    @ViewBuilder
    private func background(_ configuration: Configuration) -> some View {
        switch role {
        case .primary:
            (configuration.isPressed ? ClipDesign.accentPressed : ClipDesign.accent)
        case .secondary:
            (configuration.isPressed ? ClipDesign.surfaceSoft : ClipDesign.paperStrong)
        case .quiet:
            Color.clear
        }
    }
}

struct PaperTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .font(ClipFont.regular(17))
            .foregroundStyle(ClipDesign.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(ClipDesign.paperStrong)
            .clipShape(RoundedRectangle(cornerRadius: ClipDesign.controlRadius))
            .overlay {
                RoundedRectangle(cornerRadius: ClipDesign.controlRadius)
                    .stroke(ClipDesign.hairline, lineWidth: ClipDesign.hairlineWidth)
            }
    }
}

struct AudioReorderDropDelegate: DropDelegate {
    let targetID: UUID
    let move: (UUID, UUID) -> Void

    func dropEntered(info: DropInfo) {
        guard let provider = info.itemProviders(for: [.text]).first else { return }
        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let value = object as? String, let sourceID = UUID(uuidString: value) else { return }
            DispatchQueue.main.async { move(sourceID, targetID) }
        }
    }

    func performDrop(info: DropInfo) -> Bool { true }
}

extension View {
    func clipCard() -> some View {
        padding(22)
            .background(ClipDesign.paperStrong)
            .clipShape(RoundedRectangle(cornerRadius: ClipDesign.cardRadius))
            .overlay {
                RoundedRectangle(cornerRadius: ClipDesign.cardRadius)
                    .stroke(ClipDesign.hairline, lineWidth: ClipDesign.hairlineWidth)
            }
            .shadow(color: ClipDesign.shadow, radius: 18, y: 10)
    }
}
