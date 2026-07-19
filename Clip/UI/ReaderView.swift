import ClipCore
import SwiftUI

struct ReaderView: View {
    let book: BookRecord

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var player: PlayerEngine
    @EnvironmentObject private var settings: ClipSettings
    @EnvironmentObject private var clipService: ClipService
    @AppStorage("Clip.Reader.TextSize") private var readerTextSize = 21.0
    @AppStorage("Clip.Reader.LineSpacing") private var readerLineSpacing = 10.0
    @State private var sentences: [SentenceRecord] = []
    @State private var timedSentences: [SentenceRecord] = []
    @State private var activeIndex: Int?
    @State private var following = true
    @State private var frames: [Int: CGRect] = [:]
    @State private var selection: ClosedRange<Int>?
    @State private var selectionAnchor: Int?
    @State private var clipping = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(sentences.indices, id: \.self) { offset in
                        let sentence = sentences[offset]
                        if offset == 0 || sentences[offset - 1].chapter != sentence.chapter {
                            chapterBreak(sentence.chapter)
                        } else if sentences[offset - 1].p != sentence.p {
                            Spacer().frame(height: 18)
                        }
                        sentenceView(sentence)
                            .id(sentence.i)
                            .background {
                                GeometryReader { geometry in
                                    Color.clear.preference(
                                        key: SentenceFrameKey.self,
                                        value: [sentence.i: geometry.frame(in: .named("readerSpace"))]
                                    )
                                }
                            }
                    }
                }
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.bottom, 34)
            }
            .coordinateSpace(name: "readerSpace")
            .simultaneousGesture(DragGesture(minimumDistance: 8).onChanged { _ in
                if selection == nil { following = false }
            })
            .simultaneousGesture(selectionGesture)
            .onPreferenceChange(SentenceFrameKey.self) { frames = $0 }
            .onChange(of: player.globalTime) { _, time in
                let next = activeSentence(at: time)
                guard next != activeIndex else { return }
                activeIndex = next
                if following, let next {
                    withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(next, anchor: .center) }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                readerFooter(proxy: proxy)
            }
        }
        .background(ClipDesign.paper.ignoresSafeArea())
        .navigationTitle(book.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                displayMenu
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
                    .font(ClipTypography.semibold())
                    .foregroundStyle(ClipDesign.ink)
            }
        }
        .toolbarBackground(ClipDesign.paper, for: .navigationBar)
        .task {
            sentences = (try? ClipDatabase.shared.sentences(bookID: book.id)) ?? []
            timedSentences = sentences.filter(\.isTimed)
            activeIndex = activeSentence(at: player.globalTime)
        }
        .accessibilityIdentifier("reader.screen")
    }

    private func chapterBreak(_ chapter: Int) -> some View {
        VStack(spacing: 8) {
            Text("❦")
                .font(ClipTypography.title(24))
                .foregroundStyle(ClipDesign.inkSecondary)
            SmallCapsLabel(text: player.chapterTitle(at: chapter))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 28)
        .padding(.bottom, 20)
    }

    private func sentenceView(_ sentence: SentenceRecord) -> some View {
        let isActive = activeIndex == sentence.i
        let isSelected = selection?.contains(sentence.i) == true
        return Text(sentence.text)
            .font(ClipTypography.body(CGFloat(readerTextSize)))
            .foregroundStyle(ClipDesign.ink)
            .lineSpacing(CGFloat(readerLineSpacing))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 10)
            .padding(.trailing, 4)
            .padding(.vertical, 3)
            .background((isActive || isSelected) ? ClipDesign.terracotta.opacity(isSelected ? 0.2 : 0.13) : Color.clear)
            .overlay(alignment: .leading) {
                if isActive || isSelected {
                    Capsule()
                        .fill(ClipDesign.terracotta)
                        .frame(width: 3)
                        .padding(.vertical, 3)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard let start = sentence.startS else { return }
                player.seek(to: start)
            }
            .accessibilityAddTraits(isActive ? .isSelected : [])
            .accessibilityHint(sentence.isTimed ? "Double tap to seek to this sentence. Long press and drag to clip a passage." : "This sentence has no audio timing.")
            .accessibilityIdentifier("reader.sentence.\(sentence.i)")
    }

    private var displayMenu: some View {
        Menu {
            Section("Text size") {
                Button {
                    readerTextSize = max(17, readerTextSize - 1)
                } label: {
                    Label("Smaller", systemImage: "textformat.size.smaller")
                }
                .disabled(readerTextSize <= 17)

                Button {
                    readerTextSize = min(29, readerTextSize + 1)
                } label: {
                    Label("Larger", systemImage: "textformat.size.larger")
                }
                .disabled(readerTextSize >= 29)
            }

            Section("Line spacing") {
                Button {
                    readerLineSpacing = max(6, readerLineSpacing - 2)
                } label: {
                    Label("Tighter", systemImage: "line.3.horizontal.decrease")
                }
                .disabled(readerLineSpacing <= 6)

                Button {
                    readerLineSpacing = min(16, readerLineSpacing + 2)
                } label: {
                    Label("Looser", systemImage: "line.3.horizontal")
                }
                .disabled(readerLineSpacing >= 16)
            }

            Divider()
            Button("Reset reading display") {
                readerTextSize = 21
                readerLineSpacing = 10
            }
        } label: {
            Label("Reading display", systemImage: "textformat.size")
                .labelStyle(.iconOnly)
                .foregroundStyle(ClipDesign.ink)
        }
        .accessibilityLabel("Reading display")
        .accessibilityIdentifier("reader.display")
    }

    private func readerFooter(proxy: ScrollViewProxy) -> some View {
        VStack(spacing: 0) {
            if !following {
                Button {
                    following = true
                    if let activeIndex {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(activeIndex, anchor: .center)
                        }
                    }
                } label: {
                    Label("Return to spoken passage", systemImage: "scope")
                        .font(ClipTypography.semibold(15))
                        .foregroundStyle(ClipDesign.paper)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(ClipDesign.ink)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.vertical, 9)
                .accessibilityIdentifier("reader.resume")
            }

            VStack(spacing: 10) {
                HStack(alignment: .center, spacing: 10) {
                    SmallCapsLabel(
                        text: following ? "Following audio" : "Browsing text",
                        color: following ? ClipDesign.accent : ClipDesign.inkSecondary
                    )
                    Spacer()
                    Text(ClipFormatters.time(player.globalTime))
                        .font(ClipTypography.time(12))
                        .foregroundStyle(ClipDesign.inkSecondary)
                        .contentTransition(.numericText())
                }

                GeometryReader { geometry in
                    let progress = book.durationS > 0
                        ? min(max(player.globalTime / book.durationS, 0), 1)
                        : 0
                    ZStack(alignment: .leading) {
                        Capsule().fill(ClipDesign.hairline).frame(height: 2)
                        Capsule().fill(ClipDesign.terracotta)
                            .frame(width: max(2, geometry.size.width * progress), height: 2)
                    }
                    .frame(maxHeight: .infinity)
                }
                .frame(height: 4)
                .accessibilityHidden(true)

                HStack(spacing: 18) {
                    readerTransportButton(
                        "gobackward.15",
                        label: "Back 15 seconds",
                        identifier: "reader.back"
                    ) {
                        player.skip(by: -15)
                    }
                    readerTransportButton(
                        player.isPlaying ? "pause.fill" : "play.fill",
                        label: player.isPlaying ? "Pause" : "Play",
                        identifier: "reader.play-pause",
                        emphasized: true
                    ) {
                        player.togglePlayback()
                    }
                    readerTransportButton(
                        "goforward.15",
                        label: "Forward 15 seconds",
                        identifier: "reader.forward"
                    ) {
                        player.skip(by: 15)
                    }

                    Spacer(minLength: 4)

                    Button {
                        guard !clipping else { return }
                        clipping = true
                        Task {
                            defer { clipping = false }
                            _ = try? await clipService.clipNow()
                        }
                    } label: {
                        Label("Clip \(settings.clipWindowSeconds)s", systemImage: "scissors")
                            .font(ClipDesign.labelFont(size: 14, weight: .semibold))
                            .foregroundStyle(ClipDesign.paper)
                            .padding(.horizontal, 13)
                            .frame(minHeight: 44)
                            .background(ClipDesign.terracotta)
                            .clipShape(RoundedRectangle(cornerRadius: ClipDesign.controlRadius))
                    }
                    .buttonStyle(.plain)
                    .disabled(clipping)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Clip the last \(settings.clipWindowSeconds) seconds to Readwise")
                    .accessibilityIdentifier("reader.clip")
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 9)
            .background(ClipDesign.paperStrong)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(ClipDesign.hairline)
                    .frame(height: ClipDesign.hairlineWidth)
            }
            .shadow(color: ClipDesign.shadow, radius: 12, y: -4)
        }
        .accessibilityElement(children: .contain)
    }

    private func readerTransportButton(
        _ symbol: String,
        label: String,
        identifier: String,
        emphasized: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: emphasized ? 21 : 18, weight: .regular))
                .foregroundStyle(emphasized ? ClipDesign.paper : ClipDesign.ink)
                .frame(width: emphasized ? 48 : 40, height: emphasized ? 48 : 40)
                .background(emphasized ? ClipDesign.accent : Color.clear)
                .clipShape(Circle())
                .overlay {
                    if !emphasized {
                        Circle().stroke(ClipDesign.hairline, lineWidth: ClipDesign.hairlineWidth)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }

    private var selectionGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.35)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("readerSpace")))
            .onChanged { value in
                guard case .second(true, let drag?) = value else { return }
                following = false
                let start = selectionAnchor ?? sentence(at: drag.startLocation)
                let end = sentence(at: drag.location)
                guard let start, let end else { return }
                selectionAnchor = start
                selection = min(start, end)...max(start, end)
            }
            .onEnded { _ in
                guard let selection else {
                    selectionAnchor = nil
                    return
                }
                Task { _ = try? await clipService.clipSelection(bookID: book.id, sentenceIndices: selection) }
                self.selection = nil
                selectionAnchor = nil
            }
    }

    private func sentence(at point: CGPoint) -> Int? {
        frames.min { lhs, rhs in
            abs(lhs.value.midY - point.y) < abs(rhs.value.midY - point.y)
        }?.key
    }

    private func activeSentence(at time: Double) -> Int? {
        var low = 0
        var high = timedSentences.count
        while low < high {
            let middle = (low + high) / 2
            if (timedSentences[middle].startS ?? .infinity) <= time { low = middle + 1 }
            else { high = middle }
        }
        guard low > 0 else { return nil }
        let candidate = timedSentences[low - 1]
        guard time <= (candidate.endS ?? -Double.infinity) else { return nil }
        return candidate.i
    }
}

private struct SentenceFrameKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
