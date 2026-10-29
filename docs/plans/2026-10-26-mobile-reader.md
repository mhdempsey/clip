# Mobile reader rebuild

The user chose both page turns and continuous scrolling, with page turns as the default. This supersedes the continuous-only reader scope in the September discovery/alignment plan; Mac discovery and alignment remain separate work.

The reader should feel like a book: coherent paragraphs, restrained audio emphasis, white/sepia/dark paper, and controls revealed with a tap. Reading location is independent of playback. Native text selection offers Highlight and Play from here. A single appearance sheet remembers font, size, spacing, margins, alignment, and reading mode across books. Contents navigation and appearance changes preserve the reading location without seeking audio.

- [x] Build UTF-16 sentence/paragraph mapping and native text layout.
- [x] Support true viewport-sized pages and continuous scrolling, preserving position on reflow.
- [x] Add persistent appearance settings, chapter navigation, and quiet reader controls.
- [x] Verify Unicode range mapping, pagination continuity, preferences, selection actions, compact-phone layouts, and larger screens.

Use the existing PlayerEngine, ClipService, and sentence database. Preserve unrelated working-tree edits. Do not publish, commit, or replace App Store assets as part of this work.

## Verification — October 27

- All 25 iOS unit tests pass, including exact-word highlight queuing, Unicode mapping, native layout, position preservation, stable audio following, accessible-size fallback, and effective margins on iPad.
- A synthetic 100,000-word book produces 1,042 pages in 0.53 seconds in the simulator. Pagination uses a single layout pass and cancels superseded reflows.
- Reader entry, page turns, rotation, appearance, continuous scrolling, contents, and native selection-menu checks pass on iPhone 13 Pro and iPad Pro 11-inch. The native-menu test waits for the player fixture and selects the opening paragraph instead of relying on a device-specific screen coordinate.
- Portrait previews are saved under `.context/reader-preview/`. Landscape screenshots produced clipped canvases; automated geometry and page-turn checks passed, but those captures are excluded from the preview set.
- LLDB attachment stalled on this machine. Unit verification used a temporary generated scheme with the debugger disabled, without changing application build settings. The temporary scheme was removed after verification.
- Existing Mac, project configuration, and App Store asset changes were preserved. No commit, push, or release was performed.

## TestFlight follow-up — October 27

The user subsequently authorized uploading the reader changes to TestFlight. Clip 1.0 (14) was successfully uploaded to App Store Connect. Xcode advanced the archive's provisional build number from 13 to 14 because 13 had already been uploaded. The project build number now matches the delivered build. Apple reported the uploaded package as processing; tester availability has not yet been verified. No Git commit or push was performed.
