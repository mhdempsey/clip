# App Privacy answers

These answers describe Clip 1.0.

## Tracking

- Does this app use data for tracking purposes? **No**
- Does this app or its third-party SDKs show advertising? **No**

## Data collection

Clip has no developer-operated account, analytics, advertising, telemetry, or
server. Imported ebooks, audiobooks, alignment data, listening position, and
settings stay on the user's devices and in Clip's private iCloud Drive
container. Apple processes iCloud data on the user's behalf.

When the user chooses to clip a passage, Clip sends the selected text, book
title, author, location, note, and clip date to the user's Readwise account.
Clip sends the Readwise API token only to Readwise, and stores it in Apple
Keychain.

Declare these data types:

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

This is deliberately conservative: it treats a user-directed Readwise export as
collection because the content is transmitted off-device to the user's
third-party account.
