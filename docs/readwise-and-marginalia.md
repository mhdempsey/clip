# Using Clip with Readwise and Marginalia

Clip uses Readwise as the durable home for audiobook highlights. Marginalia can then bring those highlights into your private reading network.

```text
spoken audiobook passage
          ↓
        Clip
          ↓
       Readwise
          ↓
      Marginalia
```

There is no direct Clip-to-Marginalia account connection. Both apps use the same Readwise account as the handoff point.

## One-time setup

### 1. Get your Readwise token

1. Sign in to Readwise.
2. Open [readwise.io/access_token](https://readwise.io/access_token).
3. Choose **Get Access Token**, then copy the token.

The token grants access to your Readwise data. Treat it like a password: do not paste it into issues, screenshots, logs, or source files.

### 2. Connect Clip to Readwise

1. Open Clip on your iPhone.
2. Open **Settings**.
3. Under **Readwise**, paste the access token.
4. Tap **Validate** and wait for **Connected**.

Clip stores the token in the iOS Keychain. It uses the token only to validate the account and send or retry highlights through the Readwise API.

### 3. Connect Marginalia to the same account

1. [Create a Marginalia account](https://ourmarginalia.com/signup) or [sign in](https://ourmarginalia.com/login).
2. Open Marginalia's Readwise connection or import flow.
3. When prompted, paste the access token from the same Readwise account used in Clip.
4. Run the initial Readwise sync.

Using the same Readwise account matters. If Clip writes to one account while Marginalia reads another, the audiobook highlights cannot appear in Marginalia.

## Everyday highlighting workflow

1. Open an aligned book in Clip and start listening.
2. Pick the amount of recent audio you want to keep: 10, 15, 20, or 30 seconds.
3. Capture it in any supported way:
   - tap **Clip** in the Listen tab;
   - invoke the Clip action from an Action Button or Shortcut;
   - use the Live Activity control; or
   - say “Clip that,” “Bookmark that,” “Highlight that,” or “Underline that.”
4. Clip selects the aligned sentences for that audio window and submits them to Readwise with the book title, author, sentence order, and an `audio @ …` timestamp.
5. Confirm the passage in Readwise when you want to check the handoff.
6. Run or refresh the Readwise sync in Marginalia to pull in newer highlights.

This ordering is intentional: verify the highlight in Readwise first, then sync Marginalia. It makes it immediately clear which half of the handoff needs attention if something is missing.

## Offline use and retries

You can make a highlight without a network connection. Clip saves it locally and retries later.

To inspect the queue:

1. Open **Clip → Settings → Pending clips**.
2. Tap **Retry** beside a waiting highlight once you are online.
3. Revalidate the Readwise token if the item says the token is invalid.
4. After it appears in Readwise, sync Marginalia again.

## Troubleshooting

### The highlight is not in Readwise

- In Clip Settings, make sure the Readwise status says **Connected**.
- Check **Pending clips** and retry the item.
- Confirm the iPhone has network access.
- If you regenerated or revoked the Readwise token, paste the new token into Clip and validate it again.

### The highlight is in Readwise but not Marginalia

- Confirm Marginalia is connected to the same Readwise account as Clip.
- Run Marginalia's Readwise sync after the highlight was created.
- If Marginalia asks for a token again, use the current token from [readwise.io/access_token](https://readwise.io/access_token).

### The captured passage is slightly early or late

- Choose a shorter or longer clip window before the next capture.
- Open **Read along** in Clip and select the exact sentences when you need a precise passage.
- Alignment quality depends on the EPUB matching the audiobook edition.

## Data boundaries

- Audiobook audio and EPUB text are not uploaded by Clip to Readwise or Marginalia.
- Transcription and text/audio alignment run on the Mac.
- Clip sends only the selected highlight text and its book metadata to Readwise.
- Marginalia obtains the highlight through the Readwise connection you configure there.

For the API contract behind Clip's Readwise handoff, see the [Readwise API documentation](https://readwise.io/api_deets).
