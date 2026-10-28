import ClipCore
import SwiftUI

struct QualitySettingsView: View {
    @ObservedObject var model: ClipMacModel
    @State private var apiKey = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Alignment")
                        .font(ClipFont.medium(28))
                        .foregroundStyle(ClipDesign.ink)
                    Text("Choose where Clip transcribes your audiobook.")
                        .font(ClipFont.regular(16))
                        .foregroundStyle(ClipDesign.inkSecondary)
                }

                Picker("Transcription", selection: $model.alignmentLocation) {
                    ForEach(AlignmentLocation.allCases) { location in
                        Text(location.title).tag(location)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("alignment-location")

                if model.alignmentLocation == .openRouter {
                    cloudSettings
                } else {
                    localSettings
                }

                HStack(spacing: 18) {
                    Link("Clip Support", destination: ClipShared.supportURL)
                        .accessibilityIdentifier("settings.support")
                    Link("Privacy Policy", destination: ClipShared.privacyPolicyURL)
                        .accessibilityIdentifier("settings.privacy-policy")
                }
                .font(ClipFont.semibold(14))
            }
            .padding(28)
        }
        .frame(width: 540, height: 600)
        .background(ClipDesign.paper)
        .tint(ClipDesign.ink)
    }

    private var localSettings: some View {
        VStack(alignment: .leading, spacing: 22) {
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
        }
    }

    private var cloudSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Whisper Large V3 · your OpenRouter account")
                .font(ClipFont.semibold(17))
            Text("Clip uploads audio to OpenRouter’s transcription providers. EPUB matching stays on this Mac. No separate provider account is needed.")
                .font(ClipFont.regular(15))
                .foregroundStyle(ClipDesign.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            SecureField(model.hasOpenRouterKey ? "Replace saved API key" : "OpenRouter API key", text: $apiKey)
                .textFieldStyle(PaperTextFieldStyle())
                .accessibilityIdentifier("openrouter-api-key")
            HStack {
                Button("Save key") {
                    if model.saveOpenRouterKey(apiKey) { apiKey = "" }
                }
                .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("openrouter-save-key")
                if model.hasOpenRouterKey {
                    Button("Remove key") { model.removeOpenRouterKey() }
                        .accessibilityIdentifier("openrouter-remove-key")
                }
                Spacer()
                Link("API keys", destination: URL(string: "https://openrouter.ai/settings/keys")!)
            }
            Text(model.credentialMessage ?? (model.hasOpenRouterKey ? "API key saved in this Mac’s Keychain." : "Your key is stored only in this Mac’s Keychain."))
                .font(ClipFont.italic(14))
                .foregroundStyle(ClipDesign.inkSecondary)
                .accessibilityIdentifier("openrouter-key-status")

            Divider()
            HStack {
                Text("Spending limit per run (USD)")
                Spacer()
                TextField("USD", value: $model.cloudSpendingLimitUSD, format: .number.precision(.fractionLength(2)))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                    .accessibilityIdentifier("openrouter-spending-limit")
            }
            .font(ClipFont.regular(15))
            Text("Clip checks spending between upload batches. Provider rate changes can put the final batch slightly over the limit. Retrying starts a new spending allowance and reuses saved chunks.")
                .font(ClipFont.regular(14))
                .foregroundStyle(ClipDesign.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("About $0.30–$1.15 for 10 hours at published rates. You’ll see an estimate before starting. Completed chunks stay on this Mac so interrupted books can resume.")
                .font(ClipFont.italic(14))
                .foregroundStyle(ClipDesign.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(ClipDesign.ink)
    }
}
