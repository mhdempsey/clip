import ClipCore
import SwiftUI

struct PlayerView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: PlayerEngine
    @EnvironmentObject private var settings: ClipSettings
    @EnvironmentObject private var clipService: ClipService
    @State private var showingReader = false
    @State private var clipping = false

    var body: some View {
        ScrollView {
            if let book = player.currentBook {
                VStack(spacing: 22) {
                    StampCover(book: book, width: 176, caption: false)
                        .padding(.top, 10)
                    VStack(spacing: 4) {
                        Text(book.title)
                            .font(ClipTypography.title(29))
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
                    ClipPrimaryButton(title: "Clip \(settings.clipWindowSeconds)s", systemImage: "scissors") {
                        guard !clipping else { return }
                        clipping = true
                        Task {
                            defer { clipping = false }
                            _ = try? await clipService.clipNow()
                        }
                    }
                    .disabled(clipping)
                    .accessibilityIdentifier("player.clip")

                    HStack {
                        Button {
                            showingReader = true
                        } label: {
                            Label("Read along", systemImage: "text.book.closed")
                                .font(ClipTypography.semibold(16))
                                .foregroundStyle(ClipDesign.ink)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("player.reader")
                        Spacer()
                        if clipService.pendingCount > 0 {
                            Text("\(clipService.pendingCount) pending")
                                .font(ClipTypography.italic(15))
                                .foregroundStyle(ClipDesign.inkSecondary)
                                .accessibilityIdentifier("player.pending")
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 36)
            } else {
                noBook
            }
        }
        .background(ClipDesign.paper.ignoresSafeArea())
        .navigationTitle("Listen")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingReader) {
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
