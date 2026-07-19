import ClipCore
import SwiftUI

struct QualitySettingsView: View {
    @ObservedObject var model: ClipMacModel

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Quality")
                    .font(ClipFont.medium(28))
                    .foregroundStyle(ClipDesign.ink)
                Text("Choose how carefully Clip listens. Standard is right for most books.")
                    .font(ClipFont.regular(16))
                    .foregroundStyle(ClipDesign.inkSecondary)
            }

            VStack(spacing: 0) {
                ForEach(AlignmentQuality.allCases) { quality in
                    Button {
                        model.quality = quality
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            ZStack {
                                Circle()
                                    .stroke(
                                        model.quality == quality ? ClipDesign.ink : ClipDesign.hairline,
                                        lineWidth: ClipDesign.hairlineWidth
                                    )
                                    .frame(width: 16, height: 16)
                                if model.quality == quality {
                                    Circle().fill(ClipDesign.ink).frame(width: 8, height: 8)
                                }
                            }
                            .padding(.top, 2)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(quality.title)
                                    .font(ClipFont.semibold(16))
                                    .foregroundStyle(ClipDesign.ink)
                                Text(quality.explanation)
                                    .font(ClipFont.regular(14))
                                    .foregroundStyle(ClipDesign.inkSecondary)
                            }
                            Spacer()
                        }
                        .padding(13)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("quality-\(quality.rawValue)")
                    if quality != AlignmentQuality.allCases.last {
                        Divider().overlay(ClipDesign.hairline)
                    }
                }
            }
            .background(ClipDesign.surface)
            .clipShape(RoundedRectangle(cornerRadius: ClipDesign.cardRadius))
            .overlay {
                RoundedRectangle(cornerRadius: ClipDesign.cardRadius)
                    .stroke(ClipDesign.hairline, lineWidth: ClipDesign.hairlineWidth)
            }

            Text("The first alignment downloads Clip’s private listening tools. Later books reuse them.")
                .font(ClipFont.italic(14))
                .foregroundStyle(ClipDesign.inkSecondary)

            HStack(spacing: 18) {
                Link("Clip Support", destination: ClipShared.supportURL)
                    .accessibilityIdentifier("settings.support")
                Link("Privacy Policy", destination: ClipShared.privacyPolicyURL)
                    .accessibilityIdentifier("settings.privacy-policy")
            }
            .font(ClipFont.semibold(14))

            Spacer()
        }
        .padding(28)
        .frame(width: 490, height: 440)
        .background(ClipDesign.paper)
        .tint(ClipDesign.ink)
    }
}
