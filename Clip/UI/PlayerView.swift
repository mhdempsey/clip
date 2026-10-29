import ClipCore
import SwiftUI

struct PlayerView: View {
    private static let bottomControlClearance: CGFloat = 112

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerEngine
    @EnvironmentObject private var settings: ClipSettings
    @EnvironmentObject private var clipService: ClipService
    @State private var showingReader = false
    @State private var clipping = false

    var body: some View {
        ScrollView {
            if let book = player.currentBook {
                VStack(spacing: contentSpacing) {
                    StampCover(book: book, width: coverWidth, caption: false)
                        .padding(.top, horizontalSizeClass == .compact ? 2 : 10)
                    VStack(spacing: 4) {
                        Text(book.title)
                            .font(ClipTypography.title(horizontalSizeClass == .compact ? 25 : 29))
                            .foregroundStyle(ClipDesign.ink)
                            .multilineTextAlignment(.center)
                        Text(book.author)
                            .font(ClipTypography.body(18))
                            .foregroundStyle(ClipDesign.inkSecondary)
                        if !player.currentChapterTitle.isEmpty {
                            SmallCapsLabel(text: player.currentChapterTitle)
                                .padding(.top, 7)
                        }
                    }

                    BookScrubber(
                        value: player.globalTime,
                        duration: book.durationS,
                        onSeek: player.seek
                    )

                    HStack(spacing: 34) {
                        transportButton("gobackward.15", label: "Back 15 seconds") { player.skip(by: -15) }
                        transportButton(player.isPlaying ? "pause" : "play", label: player.isPlaying ? "Pause" : "Play", large: true) {
                            player.togglePlayback()
                        }
                        transportButton("goforward.15", label: "Forward 15 seconds") { player.skip(by: 15) }
                    }

                    DurationStampPicker(selection: $settings.clipWindowSeconds)
                    ClipPrimaryButton(title: "Clip last \(settings.clipWindowSeconds)s", systemImage: "scissors") {
                        guard !clipping else { return }
                        clipping = true
                        Task {
                            defer { clipping = false }
                            _ = try? await clipService.clipNow()
                        }
                    }
                    .disabled(clipping)
                    .accessibilityIdentifier("player.clip")
                    Text("Or say “Clip that.” Sends the matched passage to Readwise, ready for Marginalia.")
                        .font(ClipTypography.italic(15))
                        .foregroundStyle(ClipDesign.inkSecondary)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("player.clip-payoff")

                    VStack(alignment: .trailing, spacing: 8) {
                        Button {
                            showingReader = true
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "text.book.closed")
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Read & listen")
                                        .font(ClipTypography.semibold(16))
                                    Text("Follow the ebook as the audiobook plays")
                                        .font(ClipTypography.italic(14))
                                        .foregroundStyle(ClipDesign.inkSecondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundStyle(ClipDesign.accent)
                            .padding(.horizontal, 16)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(ClipDesign.paperStrong)
                            .clipShape(RoundedRectangle(cornerRadius: ClipDesign.controlRadius))
                            .overlay {
                                RoundedRectangle(cornerRadius: ClipDesign.controlRadius)
                                    .stroke(ClipDesign.hairlineStrong, lineWidth: ClipDesign.hairlineWidth)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("player.reader")
                        if clipService.pendingCount > 0 {
                            Text("\(clipService.pendingCount) pending")
                                .font(ClipTypography.italic(15))
                                .foregroundStyle(ClipDesign.inkSecondary)
                                .accessibilityIdentifier("player.pending")
                        }
                    }

                    PlaybackSpeedControl(
                        value: player.playbackRate,
                        onChange: player.setPlaybackRate
                    )
                }
                .padding(.horizontal, horizontalSizeClass == .compact ? 20 : 28)
                .padding(.bottom, Self.bottomControlClearance)
            } else {
                noBook
            }
        }
        .background(ClipDesign.paper.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Listen")
                    .font(ClipTypography.title(21))
                    .foregroundStyle(ClipDesign.ink)
            }
        }
        .fullScreenCover(isPresented: $showingReader) {
            if let book = player.currentBook {
                NavigationStack { ReaderView(book: book) }
            }
        }
        .overlay(alignment: .bottom) {
            if let error = player.playbackError {
                Text(error)
                    .font(ClipTypography.body(15))
                    .foregroundStyle(ClipDesign.paper)
                    .padding(10)
                    .background(ClipDesign.ink)
            }
        }
        .accessibilityIdentifier("player.screen")
    }

    private var coverWidth: CGFloat {
        horizontalSizeClass == .compact ? 124 : 176
    }

    private var contentSpacing: CGFloat {
        horizontalSizeClass == .compact ? 14 : 22
    }

    private var noBook: some View {
        VStack(spacing: 16) {
            Text("❦")
                .font(ClipTypography.title(36))
                .foregroundStyle(ClipDesign.inkSecondary)
            Text("Choose a book from the Library.")
                .font(ClipTypography.body(20))
                .foregroundStyle(ClipDesign.ink)
            Button("Open Library") { model.selectedTab = .library }
                .font(ClipTypography.semibold())
                .foregroundStyle(ClipDesign.ink)
                .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 120)
    }

    private func transportButton(
        _ image: String,
        label: String,
        large: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: image)
                .font(.system(size: large ? 34 : 24, weight: .light))
                .frame(width: large ? 62 : 44, height: large ? 62 : 44)
                .foregroundStyle(ClipDesign.ink)
                .overlay {
                    if large { Circle().stroke(ClipDesign.hairline, lineWidth: ClipDesign.hairlineWidth) }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier("player.\(label.lowercased().replacingOccurrences(of: " ", with: "-"))")
    }
}

private struct PlaybackSpeedControl: View {
    let value: Double
    let onChange: (Double) -> Void

    private var formattedValue: String {
        "\(value.formatted(.number.precision(.fractionLength(1))))×"
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                SmallCapsLabel(text: "Playback speed")
                Spacer()
                Text(formattedValue)
                    .font(ClipTypography.time(15))
                    .foregroundStyle(ClipDesign.ink)
                    .contentTransition(.numericText())
            }
            Slider(
                value: Binding(get: { value }, set: onChange),
                in: ClipShared.playbackRateRange,
                step: 0.1
            ) {
                Text("Playback speed")
            } minimumValueLabel: {
                Text("1×")
            } maximumValueLabel: {
                Text("3×")
            }
            .tint(ClipDesign.terracotta)
            .font(ClipTypography.time(12))
            .foregroundStyle(ClipDesign.inkSecondary)
            .accessibilityValue("\(formattedValue) speed")
            .accessibilityIdentifier("player.speed-slider")
        }
    }
}

private struct BookScrubber: View {
    let value: Double
    let duration: Double
    let onSeek: (Double) -> Void
    @State private var dragValue: Double?

    private var shownValue: Double { dragValue ?? value }

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geometry in
                let progress = duration > 0 ? min(max(shownValue / duration, 0), 1) : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(ClipDesign.ink.opacity(0.2)).frame(height: 2)
                    Capsule().fill(ClipDesign.terracotta)
                        .frame(width: max(2, geometry.size.width * progress), height: 2)
                    Circle().fill(ClipDesign.terracotta)
                        .frame(width: 12, height: 12)
                        .offset(x: max(0, min(geometry.size.width - 12, geometry.size.width * progress - 6)))
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            dragValue = duration * min(max(gesture.location.x / geometry.size.width, 0), 1)
                        }
                        .onEnded { _ in
                            if let dragValue { onSeek(dragValue) }
                            dragValue = nil
                        }
                )
            }
            .frame(height: 22)
            HStack {
                Text(ClipFormatters.time(shownValue))
                Spacer()
                Text("−\(ClipFormatters.time(max(0, duration - shownValue)))")
            }
            .font(ClipTypography.time(13))
            .foregroundStyle(ClipDesign.inkSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Playback position")
        .accessibilityValue("\(ClipFormatters.time(shownValue)) of \(ClipFormatters.time(duration))")
        .accessibilityAdjustableAction { direction in
            onSeek(shownValue + (direction == .increment ? 15 : -15))
        }
        .accessibilityIdentifier("player.scrubber")
    }
}
