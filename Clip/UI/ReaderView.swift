import ClipCore
import SwiftUI

struct ReaderView: View {
    let book: BookRecord

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var player: PlayerEngine
    @EnvironmentObject private var settings: ClipSettings
    @EnvironmentObject private var clipService: ClipService
    @StateObject private var preferences = ReaderPreferences()
    @State private var document = ReaderDocument(sentences: [], chapterTitle: { _ in "" })
    @State private var activeIndex: Int?
    @State private var following = false
    @State private var controlsVisible = true
    @State private var showingAppearance = false
    @State private var showingContents = false
    @State private var showingSearch = false
    @State private var searchQuery = ""
    @State private var bookToolsTab = 0
    @State private var browsingSentence: Int?
    @State private var focusedRange: NSRange?
    @State private var navigation: ReaderNavigation?
    @State private var visibleCharacter = 0
    @State private var pageNumber = 1
    @State private var pageCount = 0
    @State private var clipping = false
    @State private var errorMessage: String?
    @State private var loadError = false

    private var palette: ReaderPalette { preferences.value.palette }
    private var browsing: Bool { !following }
    private var currentChapter: ReaderDocument.Chapter? {
        document.chapters.last(where: { $0.range.location <= visibleCharacter })
    }
    private var progress: Int {
        guard !document.text.isEmpty else { return 0 }
        return min(100, Int(Double(visibleCharacter) / Double(document.utf16Length) * 100))
    }
    private var locationLabel: String {
        preferences.value.mode == .pages && pageCount > 0
            ? "Page \(pageNumber) of \(pageCount)"
            : "\(progress)% read"
    }

    var body: some View {
        VStack(spacing: 0) {
            header.frame(height: 52)
            if document.passages.isEmpty {
                ContentUnavailableView {
                    Label(loadError ? "Unable to open text" : "No text available", systemImage: "book")
                } description: {
                    Text(loadError ? "Try opening this book again." : "This book does not contain readable text.")
                }
                .frame(maxHeight: .infinity)
            } else {
                ReaderTextView(
                    document: document, appearance: preferences.value,
                    activeSentence: activeIndex, following: following,
                    navigation: navigation,
                    onToggleControls: { setControlsVisible(!controlsVisible) },
                    onManualMove: {
                        following = false
                        focusedRange = nil
                        browsingSentence = nil
                        setControlsVisible(true)
                    },
                    onLocation: { character, page, count in
                        visibleCharacter = character
                        pageNumber = page
                        pageCount = count
                    },
                    onHighlight: { indices, text in saveHighlight(indices, text: text) },
                    onPlay: playFrom,
                    onReaderMove: { range in
                        browsingSentence = document.playbackSentence(in: range)?.i
                    },
                    focusedRange: focusedRange
                )
                .accessibilityIdentifier("reader.text")
            }
            footer.frame(height: 108)
        }
        .background(Color(palette.paper).ignoresSafeArea())
        .foregroundStyle(Color(palette.ink))
        .tint(Color(palette.accent))
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(preferences.value.theme == .dark ? .dark : .light)
        .sheet(isPresented: $showingAppearance) { ReaderAppearanceSheet(preferences: preferences) }
        .sheet(isPresented: $showingContents) { contents }
        .sheet(isPresented: $showingSearch) {
            ReaderSearchSheet(document: document, query: $searchQuery) { match in
                browse(to: match.range)
                showingSearch = false
            }
        }
        .alert("Clip", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
        .overlay(alignment: .top) {
            if let toast = clipService.toast {
                Text(toast)
                    .font(.system(size: 14, weight: .medium))
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .foregroundStyle(Color(palette.paper))
                    .background(Color(palette.ink), in: Capsule())
                    .padding(.top, 56)
                    .allowsHitTesting(false)
            }
        }
        .task { loadDocument() }
        .onChange(of: player.globalTime) { _, time in activeIndex = document.activeSentence(at: time) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reader.screen")
    }

    private var header: some View {
        ZStack {
            if controlsVisible {
                HStack(spacing: 8) {
                    iconButton("chevron.down", label: "Done reading", identifier: "reader.done") { dismiss() }
                    VStack(spacing: 2) {
                        Text(book.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                        if browsing { Text("Browsing · audio unchanged").font(.system(size: 9)).lineLimit(1) }
                    }
                    .frame(maxWidth: .infinity).foregroundStyle(Color(palette.secondary))
                    iconButton("magnifyingglass", label: "Search this book", identifier: "reader.search") { showingSearch = true }
                        .disabled(document.passages.isEmpty)
                    iconButton("list.bullet", label: "Contents and clips", identifier: "reader.contents") { showingContents = true }
                    Button { showingAppearance = true } label: {
                        Text("Aa").font(.system(size: 21, design: .serif)).frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .accessibilityLabel("Reading appearance")
                    .accessibilityIdentifier("reader.display")
                }
                .padding(.horizontal, 10)
            } else {
                Button { setControlsVisible(true) } label: {
                    Text(book.title)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(palette.secondary))
                        .lineLimit(1)
                        .padding(.horizontal, 50)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Show reading controls")
                .accessibilityIdentifier("reader.show-controls")
            }
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        VStack(spacing: 8) {
            if controlsVisible {
                HStack {
                    Button(action: returnToAudio) {
                        Label(following ? "Following audio" : "Return to audio", systemImage: "waveform")
                            .font(.system(size: 11, weight: .medium))
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("reader.resume")
                    Spacer()
                    Text(locationLabel).font(.system(size: 11)).monospacedDigit()
                        .foregroundStyle(Color(palette.secondary))
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .accessibilityIdentifier("reader.location")
                    if browsing {
                        Spacer()
                        Button("Play from here") {
                            if let sentence = document.passages.first(where: { $0.sentence.i == browsingSentence })?.sentence { playFrom(sentence) }
                        }
                        .font(.system(size: 11, weight: .medium)).frame(minHeight: 44)
                        .disabled(browsingSentence == nil)
                        .accessibilityIdentifier("reader.play-from-here")
                    }
                }
                HStack(spacing: 12) {
                    iconButton("gobackward.15", label: "Back 15 seconds", identifier: "reader.back") { player.skip(by: -15) }
                    playButton
                    iconButton("goforward.15", label: "Forward 15 seconds", identifier: "reader.forward") { player.skip(by: 15) }
                    Spacer(minLength: 0)
                    Button { saveHighlight(nil) } label: {
                        Label("Clip \(settings.clipWindowSeconds)s", systemImage: "scissors")
                            .font(.system(size: 13, weight: .medium))
                            .padding(.horizontal, 14)
                            .frame(minHeight: 44)
                            .foregroundStyle(Color(palette.paper))
                            .background(Color(palette.accent), in: Capsule())
                    }
                    .disabled(clipping)
                    .accessibilityLabel("Clip the last \(settings.clipWindowSeconds) seconds to Readwise")
                    .accessibilityIdentifier("reader.clip")
                }
            } else {
                Spacer(minLength: 0)
                HStack {
                    playButton
                    Spacer()
                    Button { setControlsVisible(true) } label: {
                        VStack(spacing: 4) {
                            Text(locationLabel).monospacedDigit()
                            if let currentChapter { Text(currentChapter.title).lineLimit(1) }
                        }
                        .font(.system(size: 10))
                        .foregroundStyle(Color(palette.secondary))
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("reader.location")
                    Spacer()
                    iconButton("scissors", label: "Clip the last \(settings.clipWindowSeconds) seconds", identifier: "reader.clip") { saveHighlight(nil) }
                        .disabled(clipping)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
        .buttonStyle(.plain)
    }

    private var playButton: some View {
        iconButton(player.isPlaying ? "pause.fill" : "play.fill", label: player.isPlaying ? "Pause" : "Play", identifier: "reader.play-pause") {
            player.togglePlayback()
        }
    }

    private func iconButton(_ symbol: String, label: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 18, weight: .regular)).frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }

    private var contents: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Book tools", selection: $bookToolsTab) {
                    Text("Contents").tag(0)
                    Text("Clips").tag(1)
                }
                .pickerStyle(.segmented).padding()
                .accessibilityIdentifier("reader.book-tools")
                if bookToolsTab == 1 {
                    BookClipsList(bookID: book.id) { clip in
                        if let range = document.clipRange(location: clip.location, text: clip.text) { browse(to: range) }
                        showingContents = false
                    }
                } else {
                    List(document.chapters) { chapter in
                        Button {
                            let end = document.chapters.first(where: { $0.range.location > chapter.range.location })?.range.location ?? document.utf16Length
                            browse(to: NSRange(location: chapter.range.location, length: end - chapter.range.location), highlight: false)
                            showingContents = false
                        } label: {
                            HStack {
                                Text(chapter.title).foregroundStyle(.primary)
                                Spacer()
                                if currentChapter?.id == chapter.id { Image(systemName: "checkmark").foregroundStyle(Color(palette.accent)) }
                            }
                            .frame(minHeight: 36).contentShape(Rectangle())
                        }
                        .accessibilityIdentifier("reader.chapter.\(chapter.id)")
                    }
                }
            }
            .navigationTitle("This book")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingContents = false } } }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func setControlsVisible(_ visible: Bool) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { controlsVisible = visible }
    }

    private func loadDocument() {
        do {
            let sentences = try ClipDatabase.shared.sentences(bookID: book.id)
            document = ReaderDocument(sentences: sentences, chapterTitle: player.chapterTitle(at:))
            activeIndex = document.activeSentence(at: player.globalTime)
            following = true
            let audioLocation = document.passages.first(where: { $0.sentence.i == activeIndex })?.range.location ?? 0
            visibleCharacter = audioLocation
            navigation = ReaderNavigation(character: visibleCharacter)
        } catch { loadError = true }
    }

    private func returnToAudio() {
        focusedRange = nil
        browsingSentence = nil
        following = true
        if let passage = document.passages.first(where: { $0.sentence.i == activeIndex }) {
            navigation = ReaderNavigation(character: passage.range.location)
        }
    }

    private func browse(to range: NSRange, highlight: Bool = true) {
        following = false
        controlsVisible = true
        focusedRange = highlight ? range : nil
        browsingSentence = document.playbackSentence(in: range)?.i
        navigation = ReaderNavigation(character: range.location)
    }

    private func playFrom(_ sentence: SentenceRecord) {
        guard let time = sentence.startS else { return }
        player.seek(to: time)
        activeIndex = document.activeSentence(at: time)
        player.play()
        returnToAudio()
    }

    private func saveHighlight(_ indices: ClosedRange<Int>?, text: String? = nil) {
        guard !clipping else { return }
        clipping = true
        Task {
            defer { clipping = false }
            do {
                if let indices { _ = try await clipService.clipSelection(bookID: book.id, sentenceIndices: indices, selectedText: text) }
                else { _ = try await clipService.clipNow() }
            } catch { errorMessage = "The highlight could not be saved. \(error.localizedDescription)" }
        }
    }

}
