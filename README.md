<p align="center">
  <img src="Clip/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png" width="180" alt="Clip icon: an open book, headphones, and handwritten pages in blue ink">
</p>

<h1 align="center">Clip</h1>

<p align="center"><em>easy highlights for audiobooks</em></p>

Clip turns DRM-free audiobooks into highlightable books. It is made of two native SwiftUI apps:

- **Clip for Mac** pairs audiobook files with an EPUB, transcribes the audio with WhisperKit on your Mac or through your OpenRouter account, aligns the transcript to the text, and creates a portable `.clipbook` package.
- **Clip for iPhone** imports or syncs that package, plays the audiobook at 1×–3×, and turns the last 10/15/20/30 seconds into a real text highlight in Readwise.

There is no Clip server or analytics SDK. Local alignment keeps audio and text on your devices or in your private iCloud container. Optional OpenRouter transcription uploads audio to OpenRouter’s providers; EPUB matching stays on your Mac. When you make a highlight, the selected passage and its book metadata are sent to Readwise.

## Using Clip

### 1. Prepare a book on your Mac

1. Open Clip for Mac and choose a DRM-free EPUB plus its matching `.mp3`, `.m4a`, or `.m4b` audiobook.
2. Check the title, author, and audio-file order, then choose where to transcribe the audio:

   | Option | Transcription | Setup |
   | --- | --- | --- |
   | **On this Mac** | WhisperKit runs locally; audio and EPUB matching stay on your Mac. | Choose a quality level in Settings. Clip downloads the speech model on the first run and reuses it. |
   | **OpenRouter cloud** | OpenRouter transcribes uploaded audio; EPUB matching stays on your Mac. | Use your own OpenRouter API key and credits. See the steps below. |

3. Click **Align** for local transcription, or follow the OpenRouter steps below for cloud transcription.
4. Keep the resulting `.clipbook` package in Clip's iCloud Drive folder, or move it to the iPhone directly.

#### Align with OpenRouter

1. Create an API key in your [OpenRouter account](https://openrouter.ai/settings/keys) and make sure the account has credits. You do not need a separate transcription-provider account.
2. In Clip for Mac, open **Clip → Settings…** and select **OpenRouter cloud**.
3. Paste your key and click **Save key**. Clip stores it in this Mac's Keychain; it is not included in exported books or synced to the iPhone.
4. Set **Spending limit per run (USD)** to an amount greater than zero.
5. Add your EPUB and matching audiobook, select **OpenRouter cloud** in the pairing card, and click **Review cloud alignment…**.
6. Review the estimated charge and upload disclosure, then click **Upload audio and align**. Once alignment finishes, use the resulting `.clipbook` on your iPhone as usual.

Clip uses Whisper Large V3 (`openai/whisper-large-v3`) with word timestamps. It sends overlapping three-minute audio chunks, with two uploads at a time, then matches the transcript to the EPUB on your Mac. Cloud alignment does not require downloading a local speech model.

The estimate includes chunk overlap and is shown before cache savings. Actual charges come from OpenRouter. Clip checks the spending limit between upload batches; provider rate changes can put the final batch slightly over the limit. Each confirmed retry starts a new spending allowance.

Completed transcript chunks are saved on your Mac. If alignment stops, click **Retry saved work**, or add the same unchanged audio again, to reuse completed chunks without uploading them again.

- **Spending limit reached:** raise the limit in Settings before retrying.
- **Key rejected or insufficient credits:** update the saved key or add OpenRouter credits, then retry.
- **Word timestamps missing:** retry or switch to **On this Mac**. Clip needs word timestamps to sync the audio with the text.

### 2. Open it on your iPhone

Books in Clip's iCloud Drive folder appear in the Library automatically. You can also AirDrop a `.clipbook`, open one from Files, or use the iOS share sheet. Clip copies a directly opened package into its local library, so iCloud is optional for that route.

### 3. Listen and save highlights

1. Choose the book in Library and press Play.
2. Set playback speed anywhere from 1× to 3× with the slider.
3. Choose a 10, 15, 20, or 30-second clip window.
4. Tap **Clip**, use the Action Button or Live Activity, or say “Clip that,” “Bookmark that,” “Highlight that,” or “Underline that.”

Clip finds the aligned sentences spoken during that window and sends the passage to Readwise with the title, author, reading order, and audio timestamp. If the network is unavailable, it keeps the highlight in **Settings → Pending clips** for retry.

### 4. Read your way

Open **Read & listen** from the player. Swipe left or right to turn pages, or choose continuous scrolling in **Aa → Reading mode**. The same panel remembers your font, text size, spacing, margins, alignment, and white, sepia, or dark theme across books. Tap the center of the page to reveal or hide controls, and use **Contents** to move between chapters.

Scrolling, page turns, chapter changes, and search results keep their own reading position without moving the audiobook. **Play from here** starts audio at the passage you are browsing when timing is available. **Return to audio** brings the reader back to the spoken passage and resumes following it. You can also select text to **Highlight** the selected words or **Play from here**.

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

## License

Clip is open source under the [MIT License](LICENSE).
