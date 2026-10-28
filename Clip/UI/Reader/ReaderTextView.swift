import SwiftUI
import UIKit

struct ReaderNavigation: Equatable {
    let id = UUID()
    let character: Int
}

struct ReaderTextView: UIViewControllerRepresentable {
    let document: ReaderDocument
    let appearance: ReaderAppearance
    let activeSentence: Int?
    let following: Bool
    let navigation: ReaderNavigation?
    var onToggleControls: () -> Void
    var onManualMove: () -> Void
    var onLocation: (Int, Int, Int) -> Void
    var onHighlight: (ClosedRange<Int>, String) -> Void
    var onPlay: (SentenceRecord) -> Void
    var onReaderMove: (NSRange) -> Void = { _ in }
    var focusedRange: NSRange? = nil

    func makeUIViewController(context: Context) -> ReaderTextController { ReaderTextController() }

    func updateUIViewController(_ controller: ReaderTextController, context: Context) {
        controller.configure(with: self)
    }
}

enum ReaderPaginator {
    /// Layout is isolated from the on-screen text view so a long book can reflow
    /// off the main thread. Only UTF-16 page boundaries return to the UI.
    static func ranges(in text: NSAttributedString, size: CGSize, isCancelled: @escaping () -> Bool = { false }) -> [NSRange] {
        guard text.length > 0, size.width > 0, size.height > 0, !isCancelled() else { return [] }
        let storage = NSTextStorage(attributedString: text)
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: CGSize(width: size.width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        var pages: [NSRange] = []
        var pageStart = 0
        var pageTop: CGFloat?
        var cannotFit = false
        // Lay out prose once, then break at existing line boundaries. A chain
        // of page-sized containers repeatedly typesets very long paragraphs.
        layout.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: layout.numberOfGlyphs)) { rect, _, _, glyphs, stop in
            guard !isCancelled(), rect.height <= size.height + 1 else {
                cannotFit = true
                stop.pointee = true
                return
            }
            let characters = layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
            if let top = pageTop, rect.maxY - top > size.height + 1, characters.location > pageStart {
                pages.append(NSRange(location: pageStart, length: characters.location - pageStart))
                pageStart = characters.location
                pageTop = rect.minY
            } else if pageTop == nil { pageTop = rect.minY }
        }
        guard !cannotFit, !isCancelled() else { return [] }
        if pageStart < text.length { pages.append(NSRange(location: pageStart, length: text.length - pageStart)) }
        return pages
    }
}

private final class ReaderPaginationCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
}

final class ReaderTextController: UIViewController, UITextViewDelegate, UIGestureRecognizerDelegate {
    private let textView = UITextView(usingTextLayoutManager: false)
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)
    private var configuration: ReaderTextView?
    private var documentID: UUID?
    private var appearance: ReaderAppearance?
    private var attributedText = NSAttributedString(string: "")
    private var pageRanges: [NSRange] = []
    private var displayedRange = NSRange(location: 0, length: 0)
    private var page = 0
    private var anchor = 0
    private var lastNavigation: UUID?
    private var lastActiveSentence: Int?
    private var layoutSize = CGSize.zero
    private var contentSizeCategory: UIContentSizeCategory?
    private var layoutGeneration = 0
    private var renderedGeneration = -1
    private var emphasisRange: NSRange?
    private var focusEmphasisRange: NSRange?
    private var emphasisColor: UIColor?
    private var reflowing = false
    private var applyingText = false
    private var readerIsMoving = false
    private var readerNavigationSentence: Int?
    private var paginationCancellation: ReaderPaginationCancellation?

    deinit { paginationCancellation?.cancel() }

    override func loadView() {
        view = textView
        textView.isEditable = false
        textView.isSelectable = true
        textView.delegate = self
        textView.textContainer.lineFragmentPadding = 0
        textView.contentInsetAdjustmentBehavior = .never
        textView.showsVerticalScrollIndicator = false
        textView.showsHorizontalScrollIndicator = false
        textView.accessibilityIdentifier = "reader.text"
        textView.addSubview(loadingIndicator)

        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        for gesture in textView.gestureRecognizers ?? [] {
            if let existing = gesture as? UITapGestureRecognizer, existing.numberOfTapsRequired > 1 {
                tap.require(toFail: existing)
            }
        }
        textView.addGestureRecognizer(tap)
        for direction: UISwipeGestureRecognizer.Direction in [.left, .right] {
            let swipe = UISwipeGestureRecognizer(target: self, action: #selector(swiped(_:)))
            swipe.direction = direction
            swipe.delegate = self
            textView.addGestureRecognizer(swipe)
        }
        textView.accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: "Next page", actionHandler: { [weak self] _ in self?.turnPage(by: 1); return true }),
            UIAccessibilityCustomAction(name: "Previous page", actionHandler: { [weak self] _ in self?.turnPage(by: -1); return true }),
            UIAccessibilityCustomAction(name: "Toggle reading controls", actionHandler: { [weak self] _ in self?.configuration?.onToggleControls(); return true })
        ]
    }

    func configure(with value: ReaderTextView) {
        loadViewIfNeeded()
        let needsLayout = documentID != value.document.id || appearance != value.appearance
        let activeChanged = lastActiveSentence != value.activeSentence
        let readerSeek = value.activeSentence != nil && value.activeSentence == readerNavigationSentence
        if readerSeek { readerNavigationSentence = nil }
        configuration = value
        documentID = value.document.id
        appearance = value.appearance
        textView.backgroundColor = value.appearance.palette.paper
        textView.tintColor = value.appearance.palette.accent
        textView.overrideUserInterfaceStyle = value.appearance.theme == .dark ? .dark : .light

        if let navigation = value.navigation, navigation.id != lastNavigation {
            lastNavigation = navigation.id
            anchor = navigation.character
            if !needsLayout, !reflowing { navigate(to: anchor) }
        }
        if needsLayout { reflow() }
        if activeChanged {
            lastActiveSentence = value.activeSentence
            if value.following, !readerIsMoving, !readerSeek, let index = value.activeSentence, let range = value.document.sentenceRanges[index] {
                if reflowing { anchor = range.location }
                else { follow(range) }
            }
        }
        updateSpokenEmphasis()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if layoutSize != textView.bounds.size || contentSizeCategory != traitCollection.preferredContentSizeCategory {
            reflow()
        }
    }

    private func reflow() {
        guard let configuration, let appearance, textView.bounds.width > 0, textView.bounds.height > 0 else { return }
        layoutSize = textView.bounds.size
        contentSizeCategory = traitCollection.preferredContentSizeCategory
        layoutGeneration += 1
        paginationCancellation?.cancel()
        let generation = layoutGeneration
        reflowing = true
        // Center the reading column while keeping the margin control useful on iPad.
        let defaultPageWidth = 680 + ReaderAppearance().margin * 2
        let margin = appearance.margin + max(0, (layoutSize.width - defaultPageWidth) / 2)
        textView.textContainerInset = UIEdgeInsets(top: 12, left: margin, bottom: 12, right: margin)
        let size = CGSize(width: layoutSize.width - margin * 2, height: layoutSize.height - 24)
        attributedText = styledDocument(configuration.document, appearance: appearance)
        textView.isScrollEnabled = appearance.mode == .scroll
        if textView.textStorage.length == 0, attributedText.length > 0 {
            loadingIndicator.center = CGPoint(x: textView.bounds.midX, y: textView.bounds.midY)
            loadingIndicator.color = appearance.palette.secondary
            loadingIndicator.startAnimating()
        }
        textView.accessibilityHint = appearance.mode == .pages
            ? "Swipe left or right to turn pages. Tap the center to show controls. Select text for highlighting or playback."
            : "Scroll to read. Tap to show controls. Select text for highlighting or playback."

        if appearance.mode == .scroll {
            pageRanges = []
            reflowing = false
            loadingIndicator.stopAnimating()
            setDisplayedText(range: NSRange(location: 0, length: attributedText.length))
            navigate(to: anchor)
            return
        }
        let text = attributedText
        let cancellation = ReaderPaginationCancellation()
        paginationCancellation = cancellation
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + .milliseconds(100)) { [weak self] in
            let ranges = ReaderPaginator.ranges(in: text, size: size, isCancelled: { cancellation.isCancelled })
            DispatchQueue.main.async {
                guard let self, self.layoutGeneration == generation else { return }
                self.pageRanges = ranges
                self.reflowing = false
                self.loadingIndicator.stopAnimating()
                if ranges.isEmpty, text.length > 0 {
                    // A very large accessibility font can exceed a landscape
                    // page. Keep the prose reachable by scrolling in that case.
                    self.textView.isScrollEnabled = true
                    self.setDisplayedText(range: NSRange(location: 0, length: text.length))
                }
                self.navigate(to: self.anchor)
            }
        }
    }

    private func styledDocument(_ document: ReaderDocument, appearance: ReaderAppearance) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = appearance.lineSpacing
        paragraph.paragraphSpacing = appearance.font(compatibleWith: traitCollection).pointSize * 0.65
        paragraph.alignment = appearance.justified ? .justified : .natural
        paragraph.hyphenationFactor = appearance.justified ? 1 : 0
        let result = NSMutableAttributedString(string: document.text, attributes: [
            .font: appearance.font(compatibleWith: traitCollection),
            .foregroundColor: appearance.palette.ink,
            .paragraphStyle: paragraph
        ])
        for chapter in document.chapters {
            let heading = NSMutableParagraphStyle()
            heading.alignment = .center
            heading.paragraphSpacingBefore = 24
            heading.paragraphSpacing = 26
            result.addAttributes([
                .font: UIFontMetrics(forTextStyle: .subheadline).scaledFont(for: .systemFont(ofSize: 14, weight: .medium), compatibleWith: traitCollection),
                .foregroundColor: appearance.palette.secondary,
                .kern: 1.2,
                .paragraphStyle: heading
            ], range: chapter.range)
        }
        return result
    }

    private func follow(_ range: NSRange) {
        guard textView.isScrollEnabled else {
            if NSIntersectionRange(range, displayedRange).length == 0 { navigate(to: range.location) }
            return
        }
        let glyphs = textView.layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        let rect = textView.layoutManager.boundingRect(forGlyphRange: glyphs, in: textView.textContainer)
        let top = textView.contentOffset.y
        if rect.minY < top + textView.bounds.height * 0.12 || rect.maxY > top + textView.bounds.height * 0.82 {
            navigate(to: range.location, readingAnchor: 0.25)
        }
    }

    private func navigate(to character: Int, readingAnchor: CGFloat = 0) {
        guard let appearance else { return }
        anchor = min(max(0, character), max(0, attributedText.length - 1))
        if appearance.mode == .pages, !textView.isScrollEnabled {
            page = pageRanges.firstIndex(where: { NSLocationInRange(anchor, $0) }) ?? 0
            let range = pageRanges.indices.contains(page) ? pageRanges[page] : NSRange(location: 0, length: 0)
            if displayedRange != range || renderedGeneration != layoutGeneration {
                setDisplayedText(range: range)
            }
            anchor = range.location
        } else if attributedText.length > 0 {
            textView.layoutManager.ensureLayout(for: textView.textContainer)
            textView.layoutIfNeeded()
            let glyph = textView.layoutManager.glyphRange(forCharacterRange: NSRange(location: anchor, length: 1), actualCharacterRange: nil)
            let rect = textView.layoutManager.boundingRect(forGlyphRange: glyph, in: textView.textContainer)
            let maximum = max(0, textView.contentSize.height - textView.bounds.height)
            applyingText = true
            let offset = min(maximum, max(0, rect.minY - textView.bounds.height * readingAnchor))
            let animated = readingAnchor > 0 && textView.window != nil && !UIAccessibility.isReduceMotionEnabled
            textView.setContentOffset(CGPoint(x: 0, y: offset), animated: animated)
            applyingText = false
        }
        updateSpokenEmphasis()
        reportLocation()
    }

    private func setDisplayedText(range: NSRange) {
        applyingText = true
        renderedGeneration = layoutGeneration
        emphasisRange = nil
        focusEmphasisRange = nil
        displayedRange = range
        textView.attributedText = attributedText.attributedSubstring(from: range)
        textView.selectedRange = NSRange(location: 0, length: 0)
        textView.setContentOffset(.zero, animated: false)
        applyingText = false
    }

    private func updateSpokenEmphasis() {
        guard !applyingText, let configuration, let appearance else { return }
        var nextRange: NSRange?
        var nextFocusRange: NSRange?
        if let index = configuration.activeSentence,
           let range = configuration.document.sentenceRanges[index] {
            let intersection = NSIntersectionRange(range, displayedRange)
            if intersection.length > 0 {
                nextRange = NSRange(location: intersection.location - displayedRange.location, length: intersection.length)
            }
        }
        if let range = configuration.focusedRange {
            let intersection = NSIntersectionRange(range, displayedRange)
            if intersection.length > 0 {
                nextFocusRange = NSRange(location: intersection.location - displayedRange.location, length: intersection.length)
            }
        }
        guard nextRange != emphasisRange || nextFocusRange != focusEmphasisRange || emphasisColor != appearance.palette.spoken else { return }
        let offset = textView.contentOffset
        applyingText = true
        textView.textStorage.beginEditing()
        if let emphasisRange { textView.textStorage.removeAttribute(.backgroundColor, range: emphasisRange) }
        if let focusEmphasisRange { textView.textStorage.removeAttribute(.backgroundColor, range: focusEmphasisRange) }
        if let nextRange { textView.textStorage.addAttribute(.backgroundColor, value: appearance.palette.spoken, range: nextRange) }
        if let nextFocusRange { textView.textStorage.addAttribute(.backgroundColor, value: UIColor.systemYellow.withAlphaComponent(0.3), range: nextFocusRange) }
        textView.textStorage.endEditing()
        textView.layoutIfNeeded()
        if textView.isScrollEnabled, textView.contentOffset != offset {
            textView.setContentOffset(offset, animated: false)
        }
        emphasisRange = nextRange
        focusEmphasisRange = nextFocusRange
        emphasisColor = appearance.palette.spoken
        applyingText = false
    }

    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        guard textView.selectedRange.length == 0 else { return }
        let x = gesture.location(in: textView).x
        if !textView.isScrollEnabled, x < textView.bounds.width * 0.18 { turnPage(by: -1) }
        else if !textView.isScrollEnabled, x > textView.bounds.width * 0.82 { turnPage(by: 1) }
        else { configuration?.onToggleControls() }
    }

    @objc private func swiped(_ gesture: UISwipeGestureRecognizer) {
        turnPage(by: gesture.direction == .left ? 1 : -1)
    }

    private func turnPage(by delta: Int) {
        guard !textView.isScrollEnabled, !reflowing, textView.selectedRange.length == 0,
              pageRanges.indices.contains(page + delta) else { return }
        configuration?.onManualMove()
        page += delta
        anchor = pageRanges[page].location
        let render = {
            self.setDisplayedText(range: self.pageRanges[self.page])
            self.updateSpokenEmphasis()
        }
        if UIAccessibility.isReduceMotionEnabled { render() }
        else { UIView.transition(with: textView, duration: 0.16, options: .transitionCrossDissolve, animations: render) }
        reportLocation()
        reportReaderMove(displayedRange)
        UIAccessibility.post(notification: .pageScrolled, argument: "Page \(page + 1) of \(pageRanges.count)")
    }

    private func reportLocation() {
        let location = anchor
        let pageNumber = page + 1
        let count = pageRanges.count
        DispatchQueue.main.async { [weak self] in self?.configuration?.onLocation(location, pageNumber, count) }
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        guard textView.isScrollEnabled else { return }
        readerIsMoving = true
        configuration?.onManualMove()
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { finishReaderMove() }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { finishReaderMove() }

    private func finishReaderMove() {
        guard readerIsMoving else { return }
        readerIsMoving = false
        let rect = CGRect(
            x: 0, y: max(0, textView.contentOffset.y - textView.textContainerInset.top),
            width: textView.textContainer.size.width,
            height: max(0, textView.bounds.height - textView.textContainerInset.top - textView.textContainerInset.bottom)
        )
        let glyphs = textView.layoutManager.glyphRange(forBoundingRect: rect, in: textView.textContainer)
        let characters = textView.layoutManager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        reportReaderMove(characters)
    }

    private func reportReaderMove(_ range: NSRange) {
        readerNavigationSentence = configuration?.document.playbackSentence(in: range)?.i
        configuration?.onReaderMove(range)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !applyingText, !reflowing, textView.isScrollEnabled, attributedText.length > 0 else { return }
        let point = CGPoint(x: 0, y: max(0, textView.contentOffset.y - textView.textContainerInset.top))
        anchor = textView.layoutManager.characterIndex(for: point, in: textView.textContainer, fractionOfDistanceBetweenInsertionPoints: nil)
        reportLocation()
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer is UISwipeGestureRecognizer { return !textView.isScrollEnabled && textView.selectedRange.length == 0 }
        return textView.selectedRange.length == 0
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        guard !applyingText, textView.selectedRange.length > 0 else { return }
        configuration?.onManualMove()
    }

    func textView(_ textView: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
        guard let configuration else { return nil }
        let globalRange = NSRange(location: displayedRange.location + range.location, length: range.length)
        guard let indices = configuration.document.sentenceIndices(in: globalRange) else { return UIMenu(children: suggestedActions) }
        let selectedText = (textView.text as NSString).substring(with: range)
        var actions: [UIMenuElement] = [UIAction(title: "Highlight", image: UIImage(systemName: "highlighter")) { _ in
            configuration.onHighlight(indices, selectedText)
        }]
        if let sentence = configuration.document.passages.first(where: { indices.contains($0.sentence.i) && $0.sentence.isTimed })?.sentence {
            actions.append(UIAction(title: "Play from here", image: UIImage(systemName: "play.fill")) { _ in configuration.onPlay(sentence) })
        }
        return UIMenu(children: actions + suggestedActions)
    }
}
