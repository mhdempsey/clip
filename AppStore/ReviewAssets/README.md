# Clip App Review demo

`Clip-Demo.clipbook` is an original, synthetic fixture for App Review. Its short
text was written for Clip and its audio was generated with the macOS system
voice. It contains no third-party book content.

To rebuild the fixture:

1. Generate one audio file per paragraph from `demo-script.txt`.
2. Record each file's duration in `Clip-Demo.clipbook/sync.json`.
3. Zip the package with `./Scripts/package-review-demo.sh`.

The published ZIP is intended only to let App Review exercise import, playback,
reading, and clipping without supplying copyrighted media.
