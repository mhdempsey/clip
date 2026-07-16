import ClipCore
import SwiftUI

struct ReaderView: View {
    let book: BookRecord

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var player: PlayerEngine
    @EnvironmentObject private var clipService: ClipService
    @State private var sentences: [SentenceRecord] = []
    @State private var timedSentences: [SentenceRecord] = []
    @State private var activeIndex: Int?
    @State private var following = true
    @State private var frames: [Int: CGRect] = [:]
    @State private var selection: ClosedRange<Int>?
    @State private var selectionAnchor: Int?

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
                .padding(.horizontal, 26)
                .padding(.bottom, 100)
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
            .overlay(alignment: .bottom) {
                if !following {
                    Button {
                        following = true
                        if let activeIndex {
                            withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(activeIndex, anchor: .center) }
                        }
                    } label: {
                        Label("Resume", systemImage: "arrow.down.to.line")
                            .font(ClipTypography.semibold(15))
                            .foregroundStyle(ClipDesign.paper)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            .background(ClipDesign.ink)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 18)
                    .accessibilityIdentifier("reader.resume")
                }
            }
        }
        .background(ClipDesign.paper.ignoresSafeArea())
        .navigationTitle(book.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
                    .font(ClipTypography.semibold())
                    .foregroundStyle(ClipDesign.ink)
            }
        }
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
            .font(ClipTypography.body(20))
            .foregroundStyle(ClipDesign.ink)
            .lineSpacing(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 3)
            .padding(.vertical, 2)
            .background((isActive || isSelected) ? ClipDesign.terracotta.opacity(isSelected ? 0.2 : 0.13) : Color.clear)
            .overlay(alignment: .bottom) {
                if isActive || isSelected {
                    Rectangle().fill(ClipDesign.terracotta).frame(height: 1)
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
