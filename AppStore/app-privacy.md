# App Privacy answers

These answers describe Clip with optional OpenRouter transcription on Mac.

## Tracking

- Does this app use data for tracking purposes? **No**
- Does this app or its third-party SDKs show advertising? **No**

## Data collection

Clip has no developer-operated account, analytics, advertising, telemetry, or
server. Imported ebooks, audiobooks, alignment data, listening position, and
settings are stored on the user's devices and in Clip's private iCloud Drive
container. Apple processes iCloud data on the user's behalf.

Transcription runs locally by default. If the user chooses OpenRouter cloud
alignment, Clip sends audiobook audio to OpenRouter and its transcription
providers using the user's OpenRouter account. EPUB matching stays on the Mac.
The OpenRouter API key is stored in this Mac's Keychain and sent only to
OpenRouter. The app shows an upload disclosure and cost estimate before starting.

When the user chooses to clip a passage, Clip sends the selected text, book
title, author, location, note, and clip date to the user's Readwise account.
Clip sends the Readwise API token only to Readwise, and stores it in Apple
Keychain.

Declare these data types:

- **Audio Data** (optional OpenRouter transcription)
  - Collected: Yes
  - Purpose: App Functionality
  - Linked to the user's identity: Yes, through their OpenRouter account
  - Used for tracking: No
- **Other User Content**
  - Collected: Yes
  - Purpose: App Functionality
  - Linked to the user's identity: Yes
  - Used for tracking: No
- **Product Interaction**
  - Collected: Yes
  - Purpose: App Functionality
  - Linked to the user's identity: Yes
  - Used for tracking: No

This is deliberately conservative: it treats user-directed third-party exports
and cloud transcription as collection. These are the release answers to review
before submitting the Mac build; this file does not change App Store Connect.
See Apple's [app privacy definitions](https://developer.apple.com/app-store/app-privacy-details/).
