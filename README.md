# Clip

Clip turns DRM-free audiobooks into highlightable books. It is made of two native SwiftUI apps:

- **Clip for Mac** pairs audiobook files with an EPUB, transcribes the audio locally with WhisperKit, aligns the transcript to the text, and creates a portable `.clipbook` package.
- **Clip for iPhone** imports or syncs that package, plays the audiobook at 1×–3×, and turns the last 10/15/20/30 seconds into a real text highlight in Readwise.

There is no Clip server or analytics SDK. Audiobook audio, EPUB text, transcription, and alignment remain on your devices or in your private iCloud container. When you make a highlight, only the selected passage and its book metadata are sent to Readwise.

## Using Clip

### 1. Prepare a book on your Mac

1. Open Clip for Mac and choose a DRM-free EPUB plus its matching `.mp3`, `.m4a`, or `.m4b` audiobook.
2. Start alignment. Clip downloads its Whisper model once, then transcribes and aligns the book on your Mac.
3. Keep the resulting `.clipbook` package in Clip's iCloud Drive folder, or move it to the iPhone directly.

### 2. Open it on your iPhone

Books in Clip's iCloud Drive folder appear in the Library automatically. You can also AirDrop a `.clipbook`, open one from Files, or use the iOS share sheet. Clip copies a directly opened package into its local library, so iCloud is optional for that route.

### 3. Listen and save highlights

1. Choose the book in Library and press Play.
2. Set playback speed anywhere from 1× to 3× with the slider.
3. Choose a 10, 15, 20, or 30-second clip window.
4. Tap **Clip**, use the Action Button or Live Activity, or say “Clip that,” “Bookmark that,” “Highlight that,” or “Underline that.”

Clip finds the aligned sentences spoken during that window and sends the passage to Readwise with the title, author, reading order, and audio timestamp. If the network is unavailable, it keeps the highlight in **Settings → Pending clips** for retry.

## Getting Books
Assuming you want to do this legally as you should, many like to use [Libro](https://libro.fm/) to buy DRM-free audiobooks and [eBooks](https://www.ebooks.com/) for DRM-free ebooks.

## Readwise and Marginalia

Readwise is the bridge between Clip and [Marginalia](https://ourmarginalia.com/):

```text
Audiobook → Clip → Readwise → Marginalia
```

Clip writes each audiobook passage to Readwise; Marginalia then imports it from the same Readwise account. Start with the [Readwise access-token page](https://readwise.io/access_token), paste the token into **Clip → Settings → Readwise**, and tap **Validate**. Then connect that Readwise account at [ourmarginalia.com](https://ourmarginalia.com/) and run its Readwise sync.

See [Using Clip with Readwise and Marginalia](docs/readwise-and-marginalia.md) for the complete setup, everyday workflow, privacy notes, and troubleshooting steps.

## Requirements

- macOS 14 or later and iOS 17 or later
- Xcode 16 or newer
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- An Apple Developer team for signed device or TestFlight builds
- iCloud and App Groups configured for the identifiers in `Config/` if you want automatic device sync

## Build

```sh
xcodegen generate
swift test --package-path ClipCore
xcodebuild -scheme ClipMac -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -scheme Clip -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Swift Package Manager downloads WhisperKit, GRDB, and ZIPFoundation on the first build. Whisper speech models are downloaded by the Mac app only when alignment begins.

## Developer setup

1. Install XcodeGen and run `xcodegen generate`.
2. Open `Clip.xcodeproj`.
3. Replace `DEVELOPMENT_TEAM` in `project.yml` and `teamID` in `Config/TestFlightExportOptions.plist` with your Apple Developer team.
4. If you replace the `com.michael.clip` prefix, update the bundle IDs, App Group, iCloud container, entitlements, and exported `.clipbook` type together.
5. Regenerate the Xcode project and configure signing for the Mac app, iOS app, widget extension, and tests.
6. Sign in to iCloud on both devices if you want automatic sync.

The detailed product and `.clipbook` schema contract lives in [`clip-build-spec.md`](clip-build-spec.md).

## Privacy and input limitations

Clip accepts DRM-free `.epub`, `.mp3`, `.m4a`, and `.m4b` files. Audible, Spotify, and other DRM-protected sources are intentionally unsupported. The Readwise token is stored in the iOS Keychain and sent only to Readwise's API. Treat it like a password and never commit it to this repository.

No open-source license has been selected. The repository is public for inspection, but no additional reuse rights are granted.
