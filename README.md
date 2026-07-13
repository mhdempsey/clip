# Clip

Clip is a private, on-device audiobook companion made of two SwiftUI apps:

- **Clip for Mac** pairs DRM-free audiobook files with an EPUB, transcribes the audio with WhisperKit, aligns the transcript to the book, and writes an atomic `.clipbook` bundle to iCloud Drive.
- **Clip for iPhone** discovers those bundles, plays their audio, and saves a trailing 10/15/20/30-second passage to Readwise from the app, Siri, the Action Button, or a Live Activity.

There is no server, analytics SDK, or non-Swift runtime. Audio and books remain on the user's devices and in their private iCloud container.

## Requirements

- macOS with Xcode 16 or newer
- XcodeGen
- An Apple Developer team for signed device/TestFlight builds
- iCloud and App Groups configured for the identifiers in `Config/`

## Build

```sh
xcodegen generate
swift test --package-path ClipCore
xcodebuild -scheme ClipMac -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -scheme Clip -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Swift Package Manager downloads WhisperKit, GRDB, and ZIPFoundation on the first build. Whisper speech models are downloaded by the Mac app only when the user begins an alignment.

## Developer setup

1. Open `Clip.xcodeproj` after running XcodeGen.
2. Set your development team on the app and extension targets.
3. Keep the bundle IDs, App Group, and iCloud container names in sync if you replace the `com.michael.clip` prefix.
4. Sign in to iCloud on both devices. Add a Readwise access token in the iOS app's Settings screen.

The full product and schema contract lives in [`clip-build-spec.md`](clip-build-spec.md).

## Privacy and input limitations

Clip accepts DRM-free `.epub`, `.mp3`, `.m4a`, and `.m4b` files. Audible, Spotify, and other DRM-protected sources are intentionally unsupported. Readwise credentials are stored in Keychain and are sent only to Readwise's API.

