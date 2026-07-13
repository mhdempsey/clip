# Clip — Build Specification v1.3
### A two-app system: Clip for Mac (align) + Clip for iOS (listen & capture)

**Product in one line:** Drop an audiobook (MP3s or M4B) and its EPUB onto **Clip for Mac**; it aligns them on-device and the book appears on your iPhone via iCloud. **Clip for iOS** plays the audio; pressing a button — or saying **"Hey Siri, clip that"** (also *bookmark / highlight / underline that*) — saves the last 10/15/20/30 seconds of spoken text to Readwise. v2 adds a sentence-level read-along view. Both apps share the Marginalia design universe.

**Distribution requirement (drives the architecture):** Michael will give this to friends. Therefore:
- The Mac side is a **real SwiftUI app** — drag, drop, watch a progress bar, done. No terminal, no Python, no Homebrew, no visible model jargon beyond a Quality picker.
- **One Swift monorepo.** Transcription via **WhisperKit** (Swift/CoreML, models auto-downloaded in-app), audio decoding via AVFoundation. Zero non-Swift runtime dependencies. Both apps ship through TestFlight.
- Trade-off accepted: WhisperKit's DTW word timestamps are slightly less precise than WhisperX's wav2vec2 alignment. Sentence-level sync (our target) is unaffected; this is the right trade for a distributable app.

**How to use this document (agent instructions):**
- Build order: ClipCore package + tests → Clip for Mac → Clip for iOS. §0 items are HUMAN tasks; skip them.
- Code shown here is the contract (names, signatures, keys, values); surrounding implementation is your call. Hard constraints in §11 override convenience.
- Compile gates: `xcodegen generate`, then `xcodebuild -scheme ClipMac -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO build` and `xcodebuild -scheme Clip -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`; `swift test` in ClipCore must pass.

---

## 0. Human setup checklist (not agent work)

1. Apple Developer account; set the signing team on all three targets. Capabilities are declared in entitlement files and auto-register once a team is set.
2. Replace the placeholder org prefix `com.michael.clip` project-wide if desired (bundle IDs, App Group, iCloud container move together).
3. Sign into iCloud on Mac and iPhone (each friend uses their own Apple ID; the iCloud container is per-user, so nothing is shared between people).
4. Paste your Readwise token (readwise.io/access_token) into iOS Settings; tap Validate. Friends each use their own token.
5. **On-device Siri verification (5 min):** test each phrase in §6.8. Any phrase that alternative-app-name matching won't take → create a personal Shortcut with that exact name (instructions live in the app's Settings → Voice phrases).
6. **Distribution:** upload both apps to App Store Connect → TestFlight; invite friends by email. (Alternative for the Mac app: Developer ID + notarized DMG for direct sends.) Note: TestFlight beta review is light, but the alternative app names *Bookmark/Highlight/Underline* are the most review-sensitive piece if this ever goes to the public App Store — the per-phrase Shortcut fallback exists for exactly that.
7. Optional: assign the Clip intent to the Action Button (iPhone Settings → Action Button → Shortcut → Clip).
8. Optional (pixel parity with Marginalia): replace the default design tokens in `ClipCore/DesignSystem.swift` (§7) with exact values from Marginalia's stylesheet — one file, nothing else changes.

---

## 1. Repository layout (Swift monorepo)

```
clip/
├── project.yml                  # XcodeGen — the whole project is text-defined (§8)
├── ClipCore/                    # local Swift package shared by all targets
│   ├── Package.swift
│   ├── Sources/ClipCore/
│   │   ├── SyncModels.swift     # Codable schema + invariant validation (§2)
│   │   ├── XHTMLTextScanner.swift
│   │   ├── EPUBReader.swift     # container/OPF/spine walk (ZIPFoundation + XMLParser)
│   │   ├── SentenceSplitter.swift
│   │   ├── NumberSpeller.swift
│   │   ├── Matcher.swift        # normalize / anchor / align (§3.3)
│   │   ├── BundleWriter.swift   # .clipbook emission, atomic
│   │   ├── ReadwiseClient.swift
│   │   └── DesignSystem.swift   # tokens for BOTH apps (§7)
│   └── Tests/ClipCoreTests/     # matcher, scanner, splitter, schema (§3.5)
├── ClipMac/                     # macOS app target sources (§4)
├── Clip/                        # iOS app target sources (§6)
├── ClipWidgets/                 # iOS Live Activity extension
├── Config/                      # entitlements + Info.plist fragments per target
└── README.md
```

---

## 2. The `.clipbook` bundle & sync.json (authoritative schema)

```
Moby-Dick.clipbook/
├── audio/part01.m4a ...         # 1..n files, passthrough (no re-encode), global timeline via offsets
├── sync.json
├── cover.jpg                    # from EPUB cover item or M4B artwork, if present
└── source.epub                  # kept for future styling / re-alignment
```

```json
{
  "version": 1,
  "book": {
    "title": "Moby-Dick",
    "author": "Herman Melville",
    "duration_s": 34215.6,
    "aligner": {"engine": "whisperkit", "model": "large-v3-turbo", "coverage": 0.984, "created": "2026-07-12"}
  },
  "audio": [
    {"file": "audio/part01.m4a", "offset_s": 0.0, "duration_s": 18000.2}
  ],
  "chapters": [
    {"title": "Chapter 1 — Loomings", "start_s": 24.8, "epub_href": "ch01.xhtml"}
  ],
  "sentences": [
    {
      "i": 0,
      "start_s": 24.80,
      "end_s": 27.12,
      "text": "Call me Ishmael.",
      "chapter": 0,
      "p": 14,
      "epub": {"href": "ch01.xhtml", "char_start": 512, "char_end": 529},
      "conf": 0.97,
      "words": [
        {"w": "Call", "s": 24.80, "e": 25.01},
        {"w": "me", "s": 25.01, "e": 25.14},
        {"w": "Ishmael.", "s": 25.14, "e": 25.72}
      ]
    }
  ]
}
```

Field contract (validated by `SyncModels.validate()`, used by tests, the Mac writer, and the iOS importer):
- All timestamps are **global seconds** into the concatenated audio timeline; players map global → (file, local) via `audio[]` offsets.
- `sentences` sorted by `i`; timed sentences non-decreasing in `start_s`; spans may touch but not overlap by >0.25 s.
- Unmatched sentences (front/back matter, missing narration): `start_s`/`end_s`/`words` = null, `conf` = 0; they keep `i`, `p`, `epub` so the reader view renders them.
- `words` stored for every timed sentence even though no v1/v2 feature reads them (word-level features must never require re-transcription). ~10–20 MB JSON per 10 h book is fine.
- `p` = paragraph ordinal across the whole book; drives paragraph breaks in the reader.
- `conf` ∈ [0,1]: fraction of the sentence's normalized tokens matched directly (interpolated timings scale ×0.5).

---

## 3. ClipCore — the shared engine

### 3.1 EPUBReader + XHTMLTextScanner
- Unzip with ZIPFoundation; parse `META-INF/container.xml` → OPF → spine order with Foundation `XMLParser`. Skip nav/toc/cover docs (epub properties or filename heuristics).
- `XHTMLTextScanner` is a hand-rolled scanner over each XHTML string (XHTML is well-formed XML): tracks in-tag state, decodes entities (`&amp; &lt; &gt; &quot; &#…;` + common named), skips comments/CDATA/`<script|style>`, and **records the source-string index of every emitted text character** (the offset map behind `epub.char_start/char_end`). Block-level tags (`p, h1–h6, li, blockquote, div` when it directly contains text) emit paragraph breaks; headings also emit chapter-split markers.
- Chapters: one per spine doc by default; split further at `h1/h2` when a doc holds several. Title = heading text or doc title.

### 3.2 SentenceSplitter + NumberSpeller
- `NLTokenizer(unit: .sentence)` plus a guard list for common abbreviations (Mr., Mrs., Dr., St., vs., e.g., i.e., etc.). Imperfect splits are acceptable — matching is token-level and sentence spans derive from token matches, so a bad split degrades gracefully.
- `NumberSpeller`: integers 0…999,999 → words, ordinals ("3rd"→"third"), four-digit years as pairs ("1984"→"nineteen eighty-four"). Unit-tested table.

### 3.3 Matcher (pure functions; the algorithmic heart)
1. `normalize(token)`: lowercase, NFKD fold, strip punctuation/quotes/dashes, digits→words via NumberSpeller, drop empties.
2. Build normalized token streams: book (back-pointers to sentence + word index) and transcript (timestamps).
3. **Anchoring:** hash all 6-gram windows of both streams; anchors = 6-grams unique in both; keep the longest increasing subsequence on transcript position (monotonic anchors) → ordered anchor pairs partitioning both streams.
4. **Windowed alignment:** per inter-anchor window (cap 4,000×4,000 tokens; larger → recursively re-anchor with 4-grams), Needleman–Wunsch over tokens: match +2 exact, +1 similar (Jaro-Winkler or Levenshtein ratio ≥ 0.85 — implement a small ratio fn, no dependency), mismatch −1, gap −1.
5. **Sentence timing:** per book sentence, matched transcript words → `start_s` = first match start, `end_s` = last match end; `conf` = matched/total. Zero matches with both timed neighbors ≤30 s apart → linear interpolation, `conf ×0.5`; otherwise untimed (nulls).
6. Enforce monotonic non-overlap (clip overlaps at the midpoint). `words` = the sentence's matched transcript words (transcript casing).

### 3.4 BundleWriter
- Assemble in a temp directory, then **atomic-rename** the finished `.clipbook` into the destination so iCloud never syncs a half-built bundle. Audio passthrough (no re-encode). Compute a coverage report struct (sentence coverage %, untimed spans >60 s, per-chapter first/last timestamps) that the Mac UI renders.

### 3.5 Tests (swift test; no model downloads, no audio files)
- `MatcherTests`: fabricate book text + synthetic transcript (same words with generated timestamps, plus noise: 5% substitutions, an inserted 40-word narrator intro, one deleted paragraph). Assert ≥95% of sentences timed, intro untimed, deleted-paragraph sentences untimed, monotonic, conf bounds, overlap ≤0.25 s.
- `XHTMLTextScannerTests`: entity decoding; offsets round-trip — re-extracting `xhtml[char_start..<char_end]` and stripping tags/whitespace equals the sentence text.
- `SentenceSplitterTests`, `NumberSpellerTests`, `SyncModelsTests` (validator catches overlap/unsorted/missing fields).

---

## 4. Clip for Mac (SwiftUI, macOS 14+)

**Feel:** a small, warm utility your least technical friend can use. Marginalia paper-and-ink (§7). One window. No jargon.

### 4.1 Flow
1. **Drop zone** (empty state): a large paper card with a hairline *dashed* border and the line "Drop a book and its audiobook." Accepts one `.epub` + one-or-many audio files (`.mp3 .m4a .m4b`) in any order/combination of drops; also a "Choose files…" button (sandbox access via drag or open panel). When only half a pair is present, the card shows what's still needed ("Got the book — now the audio").
2. **Pairing card:** stamp-framed cover (from EPUB), title/author (editable text fields, pre-filled from metadata), file list, an **Align** button (terracotta — the Mac's primary verb).
3. **Job progress:** one card per job with a stage label and bar — *Preparing → Listening (transcribing) 42% → Matching → Writing* — plus a friendly time estimate. Jobs queue serially. WhisperKit progress callbacks drive the bar. Wrap the job in `ProcessInfo.beginActivity(.idleSystemSleepDisabled, …)` so a closed-lid nap doesn't kill it; app quits are resisted with a confirm sheet while a job runs.
4. **Done card:** coverage as plain language — "Aligned 98% of the book" — with a caution state below 90%: "This audio doesn't fully match this book (43%) — abridged, or a different edition?" plus a details disclosure (largest unmatched spans). Buttons: *Reveal in Finder*, and the line "In your iCloud — it'll appear in Clip on your iPhone."
5. **Shelf tab:** stamp-grid of finished books from the iCloud container; per-book context menu: Re-align…, Reveal in Finder, Remove.

### 4.2 Transcription (WhisperKit)
- SPM: `https://github.com/argmaxinc/WhisperKit`. `DecodingOptions(wordTimestamps: true)`; feed audio files directly (WhisperKit/AVFoundation handle decode). Convert file-local word times to global via `audio[]` offsets.
- **Models are a Quality setting, not a concept:** Settings → Quality: *Standard* (large-v3-turbo, default) / *Maximum* (large-v3) / *Fast test* (base). First alignment triggers an in-app model download with a progress bar and a one-time sentence of explanation ("Clip downloads a speech model once (~1.5 GB) and everything runs privately on your Mac."). Models cache in Application Support.
- Transcript cache keyed by SHA-256 of the audio set, so re-aligns skip the Listening stage.
- Duration/chapter metadata via `AVAsset` (`load(.duration)`, `loadChapterMetadataGroups` for M4B — chapter atoms are a sanity signal only, never authoritative).
- Expectation to encode in the UI estimate: roughly 10–40 min per 10 h book on Apple Silicon, model-dependent.

### 4.3 Output
- Destination: the iCloud container's Documents (visible to users as the **Clip** folder in iCloud Drive). If iCloud is unavailable, fall back to `~/Documents/Clip/` and say so in the done card.
- App Sandbox on (TestFlight requires it); user-selected/dropped files grant read access; container + Application Support cover everything else.

**Acceptance (Mac):** human drops a LibriVox MP3 set + matching Gutenberg EPUB; app produces a bundle with coverage ≥ 0.90 that passes `SyncModels.validate()`, and the book appears in the iOS app on the same Apple ID.

---

## 5. Transfer: iCloud glue (both apps)

- Shared container `iCloud.com.michael.clip`, services CloudDocuments; Info.plist `NSUbiquitousContainers → {NSUbiquitousContainerIsDocumentScopePublic: true, NSUbiquitousContainerName: "Clip"}` (Mac target) so the folder is user-visible.
- iOS discovery: `NSMetadataQuery` (`NSMetadataQueryUbiquitousDocumentsScope`, `*.clipbook`); call `startDownloadingUbiquitousItem(at:)` for remote items; surface `NSMetadataUbiquitousItemPercentDownloadedKey` as per-book progress in the Library.
- On first open of a bundle, ingest `sync.json` into GRDB (§6.4); stream audio from container URLs (never copy audio out).
- Bundle updated on Mac (re-align) → importer re-ingests on `sync.json` mtime change; playback position is preserved.

---

## 6. Clip for iOS (SwiftUI, iOS 17+)

### 6.1 Identity
- Bundle IDs: app `com.michael.clip`, widget `com.michael.clip.widgets`; App Group `group.com.michael.clip` (shared defaults + GRDB db). Display name **Clip**.

### 6.2 Capabilities / Info.plist
- Entitlements: App Groups (app+widget); iCloud CloudDocuments (app); Siri (app). Background Modes: `audio`. `NSSupportsLiveActivities = true`.
- **Alternative app names** (this is what makes the extra Siri verbs work):

```xml
<key>INAlternativeAppNames</key>
<array>
  <dict><key>INAlternativeAppName</key><string>Bookmark</string></dict>
  <dict><key>INAlternativeAppName</key><string>Highlight</string></dict>
  <dict><key>INAlternativeAppName</key><string>Underline</string></dict>
</array>
```

### 6.3 Source layout

```
Clip/
├── ClipApp.swift
├── Data/ (Database.swift, BundleImporter.swift, SyncStore.swift)
├── Playback/ (PlayerEngine.swift, NowPlaying.swift)
├── Clipping/ (ClipIntent.swift, PlayPauseIntent.swift, ClipShortcuts.swift, ClipService.swift)
├── UI/ (LibraryView.swift, PlayerView.swift, SettingsView.swift, ReaderView.swift)
└── Support/ (AppGroup.swift, Haptics.swift, Fonts/EBGaramond-*.ttf + OFL.txt)
```
(ReadwiseClient and DesignSystem come from ClipCore.)

### 6.4 GRDB schema (db in App Group container: `clip.sqlite`)

```sql
CREATE TABLE book(id TEXT PRIMARY KEY, title TEXT, author TEXT, bundleURL TEXT,
                  durationS REAL, coverPath TEXT, positionS REAL DEFAULT 0,
                  addedAt DATE, lastPlayedAt DATE);
CREATE TABLE sentence(bookId TEXT, i INTEGER, startS REAL, endS REAL, text TEXT,
                      chapter INTEGER, p INTEGER, conf REAL,
                      PRIMARY KEY(bookId, i));           -- words stay in sync.json, not DB
CREATE INDEX sentence_time ON sentence(bookId, startS);
CREATE TABLE clip_queue(id TEXT PRIMARY KEY, bookId TEXT, text TEXT, note TEXT,
                        location INTEGER, createdAt DATE, sentAt DATE NULL,
                        attempts INTEGER DEFAULT 0, lastError TEXT NULL);
```

`SyncStore` contract: `sentences(bookId:overlapping range: ClosedRange<Double>) -> [Sentence]` — index-backed binary search; whole sentences whose span intersects the range, `conf > 0`, clamped to the chapter containing the range's upper bound.

### 6.5 PlayerEngine
- `@MainActor` singleton publishing `currentBook`, `globalTime`, `isPlaying`. `AVAudioSession` category `.playback`; `AVQueuePlayer` over the bundle's files; global-time seek via `audio[]` offsets.
- Persist position (debounced 5 s + on pause/background) to GRDB **and** App Group defaults (`currentBookId`, `currentPositionS`) so the intent path can always answer.
- **Interruption anchor (critical):** observe `AVAudioSession.interruptionNotification`; on `.began`, stamp `lastInterruptionPositionS` + wall time into App Group defaults. `clipAnchorTime()` returns that stamp if <10 s old, else live `globalTime`, else persisted position. *Siri ducks audio before the intent runs; the window must end where the user spoke — and because the window trails backward, Siri's latency costs nothing.*
- Remote commands: play/pause, ±15 s, scrub; Now Playing metadata + artwork.

### 6.6 Clip duration — the simple UI (fixed values: 10/15/20/30)
- Single source of truth: App Group key `clipWindowSeconds: Int`, default **15**, allowed `[10, 15, 20, 30]`.
- **PlayerView:** four stamp-chips directly beneath the transport — `10s 15s 20s 30s` (§7 styling) — bound to that key; the Clip button's label reflects it live ("Clip 15s").
- **SettingsView:** the same picker as "Default clip length". **ClipIntent** reads the key at perform-time; the **Live Activity** button label shows the current value.

### 6.7 ClipIntent + ClipService

```swift
import AppIntents

struct ClipIntent: LiveActivityIntent {          // runs in the app's process (player is alive)
    static let title: LocalizedStringResource = "Clip"
    static let description = IntentDescription("Save the last few spoken seconds to Readwise.")
    static let openAppWhenRun = false
    static var authenticationPolicy: IntentAuthenticationPolicy { .alwaysAllowed } // lock-screen capture

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let result = try await ClipService.shared.clipNow() else {
            return .result(dialog: "Nothing is playing.")
        }
        return .result(dialog: result.queuedOffline ? "Clipped. I'll sync it later." : "Clipped.")
    }
}
```

`ClipService.clipNow()`:
1. `t = PlayerEngine.shared.clipAnchorTime()`; `w = Double(clipWindowSeconds)`.
2. `sentences = SyncStore.sentences(overlapping: (t−w)...t)`; if empty, widen once to `(t−w−5)...t`; still empty → clip the single sentence containing `t`; no book/position at all → nil ("Nothing is playing").
3. Compose text with paragraph breaks (`\n\n` on `p` change). Note: `"audio @ h:mm:ss"`. Location = first sentence `i`.
4. Insert into `clip_queue`; attempt immediate send; else leave queued. `.success` haptic + ❦ toast when foregrounded.
5. Retries: on foreground, on play start, and `BGAppRefreshTask` (`com.michael.clip.flush`); oldest-first, exponential backoff via `attempts`, flag after 10 failures (visible in Settings → Pending clips).

### 6.8 Siri wiring

```swift
struct ClipShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ClipIntent(),
            phrases: [
                "\(.applicationName) that",          // Clip / Bookmark / Highlight / Underline that
                "\(.applicationName) this",
                "\(.applicationName) the last part",
                "Save that in \(.applicationName)",
                "Clip that in \(.applicationName)"
            ],
            shortTitle: "Clip",
            systemImageName: "scissors"
        )
    }
}
```
- Every phrase must contain `\(.applicationName)`; the §6.2 alternative names make `"\(.applicationName) that"` also match **"Bookmark that" / "Highlight that" / "Underline that."**
- Verification is human (§0.5). Per-phrase fallback: a personal Shortcut named exactly "Bookmark that" (etc.) wrapping the Clip action — Siri runs personal shortcuts verbatim by name. SettingsView → "Voice phrases" documents this for friends.
- Free once the intent exists: Action Button, Back Tap, Control Center, Apple Watch Shortcuts.

### 6.9 Live Activity (ClipWidgets)
- `ClipActivityAttributes` (bookId, title, author) + `ContentState` (elapsedS, durationS, isPlaying, windowSeconds).
- Lock Screen: artwork thumb, title, progress, two `Button(intent:)` — Play/Pause (`PlayPauseIntent`, also `LiveActivityIntent`) and **"Clip ⟨N⟩s"** (`ClipIntent`). Dynamic Island: compact scissors; expanded = both buttons. Start on play, local updates (~30 s + state changes), end on stop/finish. Palette per §7.

### 6.10 Screens
- **LibraryView:** stamp-grid of covers (GRDB + in-flight iCloud downloads with progress); pull-to-refresh re-runs the metadata query; context menu: Delete local copy.
- **PlayerView:** artwork, title/author, chapter label, scrubber, −15/play/+15, duration chips (§6.6), big terracotta Clip button, queued-clip badge.
- **SettingsView:** Readwise token (SecureField → Keychain; Validate calls `GET https://readwise.io/api/v2/auth/`, expects 204), Default clip length, Pending clips (retry/delete), Voice phrases help, version.
- **ReaderView (v2, milestone 7):** vertical text from GRDB sentences grouped by `p`/chapter; active sentence via 0.5 s `periodicTimeObserver` + binary search; auto-scroll **with hysteresis** (manual scroll pauses following; floating "Resume" pill); tap sentence → seek; long-press drag-select → same ClipService path. Untimed sentences render normally, non-tappable. Typography per §7.

### 6.11 ReadwiseClient (ClipCore)
- `POST https://readwise.io/api/v2/highlights/`, header `Authorization: Token <token>`, body `{"highlights":[{"text": …, "title": book.title, "author": book.author, "source_type": "clip", "category": "books", "location": <sentence i>, "location_type": "order", "note": "audio @ 4:32:18", "highlighted_at": ISO8601}]}`.
- 2xx = sent; 401 → "token invalid" surfaced in Settings; 429/5xx → requeue with backoff. Never resend a `clip_queue.id` after a 2xx.

---

## 7. Design language — the Marginalia universe (governs BOTH apps)

Clip is Marginalia's sibling: the capture tool beside the library. Same paper, same ink, one terracotta accent doing the work the bloom cards do there. Both apps should read as well-set books that happen to handle audio — never as media apps or dev tools. All values live in `ClipCore/DesignSystem.swift`; views consume tokens, never literals. Defaults below are same-family; §0.8 swaps in exact values for pixel parity.

**Palette (light / dark):**

| Token | Light | Dark |
|---|---|---|
| `paper` (background) | `#F7F2E6` | `#15110B` |
| `surface` (cards) | `#FCF8EF` | `#1E1912` |
| `ink` (primary text) | `#1E1A13` | `#EDE5D3` |
| `inkSecondary` | `#6E6455` | `#A79B85` |
| `hairline` (rules, borders) | `#D9CFBB` | `#342D21` |
| `terracotta` (the accent) | `#C2542B` | `#CE6B43` |
| `terracottaPressed` | `#A64621` | `#B5552F` |

Dark mode is reading by lamplight: deep espresso paper, cream ink, terracotta unchanged in role.

**Typography.** EB Garamond throughout — bundle static weights (Regular, Medium, SemiBold, Italic; Google Fonts, SIL OFL license file included; `UIAppFonts` on iOS, `ATSApplicationFontsPath`/resource registration on macOS). Reading text (ReaderView): 20 pt, ~1.5 line height, ragged right, ≥24 pt margins. Titles: Medium. Buttons, chapter heads, captions, stage labels: `.smallCaps()` with slight tracking. Single exception: tabular-figure system font for time readouts. Sentence case; microcopy spare and literary ("Clipped." · "The shelf is empty — align a book on your Mac and it will appear here." · "Listening…" for the transcription stage).

**Terracotta means the primary verb of the surface, nothing else.** iOS: the Clip button (player, Live Activity, reader selection bar). Mac: the Align button and active job progress. Everything else is ink on paper; system accent/blue must never appear.

**Signature elements (the same-universe tells):**
- *Postage-stamp covers:* covers sit in a reusable `StampFrame` modifier — cream mat, hairline ink border, perforated edge (scalloped alpha mask: 3 pt semicircle cutouts at 6 pt pitch), small-caps caption beneath. Used in the iOS Library and the Mac shelf/pairing card.
- *Ornaments:* a fleuron ❦ (EB Garamond, `inkSecondary`) separates chapters in ReaderView and closes the Mac done-card. Clipped sentences carry a terracotta pencil-weight underline + a small terracotta ¶ in the margin — literal marginalia.
- *Active sentence (v2):* terracotta wash at 12–15% opacity + 1 pt terracotta underline. Pencil, never neon highlighter.
- *Duration picker:* four stamp-chips (hairline ink outline on cream; selected = terracotta fill, paper text).
- *Mac drop zone:* paper card, hairline *dashed* border, centered small-caps invitation line; on hover-with-files the border turns terracotta.
- *Scrubber / progress bars:* hairline track (ink 20%), terracotta fill, small round thumb.
- *Confirmation:* `.success` haptic (iOS) + a brief toast — ❦ *Clipped.* — EB Garamond Italic.
- *App icons (both):* cream field, stamp-perforated hairline border; iOS: terracotta scissors resting on an ink baseline rule; Mac: the same scissors beside a small ink waveform. Vector-drawn.

**Restraint rules:** hairline borders instead of shadows (paper doesn't float); no gradients, no glassmorphism, no filled SF Symbol styles for primary actions (line-weight symbols in ink are fine); radius 8 pt cards / 6 pt controls; when in doubt add margin, not chrome. Live Activity/Dynamic Island: styling is constrained, but every widget color comes from the palette — ink surface, cream text, terracotta Clip button — so the lock screen reads as the same object.

---

## 8. Project generation — `project.yml` (XcodeGen)

```yaml
name: Clip
options: { bundleIdPrefix: com.michael, deploymentTarget: { iOS: "17.0", macOS: "14.0" } }
packages:
  ClipCore:  { path: ClipCore }
  GRDB:      { url: https://github.com/groue/GRDB.swift, from: "6.27.0" }
  WhisperKit:{ url: https://github.com/argmaxinc/WhisperKit, from: "0.9.0" }
  ZIPFoundation: { url: https://github.com/weichsel/ZIPFoundation, from: "0.9.16" }
targets:
  ClipMac:
    type: application
    platform: macOS
    sources: [ClipMac]
    dependencies: [ {package: ClipCore}, {package: WhisperKit}, {package: ZIPFoundation} ]
    entitlements: { path: Config/ClipMac.entitlements }   # sandbox, iCloud CloudDocuments
    info:
      path: Config/ClipMac-Info.plist
      properties:
        NSUbiquitousContainers:
          iCloud.com.michael.clip:
            NSUbiquitousContainerIsDocumentScopePublic: true
            NSUbiquitousContainerName: "Clip"
  Clip:
    type: application
    platform: iOS
    sources: [Clip]
    dependencies: [ {package: ClipCore}, {package: GRDB}, {target: ClipWidgets} ]
    entitlements: { path: Config/Clip.entitlements }      # app group, iCloud, Siri
    info:
      path: Config/Clip-Info.plist
      properties:
        UIBackgroundModes: [audio]
        NSSupportsLiveActivities: true
        NSSiriUsageDescription: "Clip uses Siri to save highlights while you listen."
        UIAppFonts: [EBGaramond-Regular.ttf, EBGaramond-Medium.ttf,
                     EBGaramond-SemiBold.ttf, EBGaramond-Italic.ttf]
        INAlternativeAppNames:
          - { INAlternativeAppName: Bookmark }
          - { INAlternativeAppName: Highlight }
          - { INAlternativeAppName: Underline }
  ClipWidgets:
    type: app-extension
    platform: iOS
    sources: [ClipWidgets]
    dependencies: [ {package: ClipCore}, {package: GRDB} ]
    entitlements: { path: Config/ClipWidgets.entitlements } # app group
    info: { path: Config/ClipWidgets-Info.plist,
            properties: { NSExtension: { NSExtensionPointIdentifier: com.apple.widgetkit-extension } } }
```

---

## 9. Milestones & acceptance criteria

| # | Milestone | Done when |
|---|-----------|-----------|
| 1 | ClipCore engine | `swift test` green per §3.5 |
| 2 | Mac app happy path | §4 acceptance: drop → aligned bundle ≥0.90 coverage → visible on iPhone |
| 3 | Validation vs Storyteller | Same 2 books through Storyteller's Docker; 10 random seeks each, drift ≤ ±2 s (human eyeballs) |
| 4 | iOS shell | Library from iCloud, background playback, Now Playing, position persists across relaunch |
| 5 | **MVP** | "Hey Siri, clip that" with phone locked + AirPods → correct trailing-window highlight in Readwise; duration chips change the window; offline clip queues and flushes |
| 6 | Live Activity | Lock-screen / Dynamic Island Clip button fires the same path |
| 7 | v2 Reader | Read-along per §6.10 incl. tap-to-seek and manual highlight |
| 8 | Friends-ready | Both apps through TestFlight; a non-technical tester aligns and clips a book with no verbal instructions beyond §0's Siri note |

Compile gates for every milestone: the three `xcodebuild`/`swift test` commands in the header succeed.

---

## 10. Edge cases (handle explicitly)
- Multi-file audio out of order → natural-sort filenames; show the assumed order in the pairing card so a human can re-drag to fix.
- Abridged/wrong-edition audio → coverage caution state (§4.1.4); never emit silently misaligned data.
- Drop of mismatched pair (e.g., two EPUBs) → friendly inline correction, never a modal error.
- Clip at book start (t < window) → clamp to 0. Clip spanning a chapter boundary → clamp to the chapter containing t.
- Two Siri clips within 5 s → both allowed (distinct queue rows).
- iCloud off / not signed in → Mac falls back to `~/Documents/Clip/` and says so; iOS Library shows a one-line explainer.
- No book ever played → intent dialog "Nothing is playing."
- Untimed region → clip falls back to nearest preceding timed sentence; note flags "approximate."

## 11. Hard constraints
- No server component anywhere. No analytics. Readwise token only in Keychain. All processing on-device.
- Swift-only runtime: no Python, no ffmpeg, no Homebrew prerequisites for end users.
- The iOS app never parses EPUB; `sync.json`/GRDB is the sole text source (source.epub is dormant until a future styling feature).
- DRM-free inputs only (Spotify/Audible files are out of scope by design).
- `words` arrays must be produced and stored even though no v1/v2 feature reads them.
- All decided product values are fixed: app name **Clip**; windows **10/15/20/30 s** (default 15); phrases **clip/bookmark/highlight/underline that**; sentence-level (not word-level) highlighting in v2; Mac side is a GUI app suitable for non-technical friends.
- Design tokens per §7 are binding on both apps: EB Garamond, paper/ink palette, terracotta reserved for the primary verb, hairlines over shadows. System-default blue/accent styling anywhere is a defect.
