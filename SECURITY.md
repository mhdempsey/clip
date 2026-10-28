# Security

Clip uses your own Readwise and OpenRouter credentials. Enter them in the app's
settings; never put real credentials in source code, test fixtures, issues, or
screenshots.

- Readwise tokens and OpenRouter keys are stored in Apple Keychain with
  device-only accessibility. Keys are not stored in book packages, transcript
  caches, or preferences.
- Credentialed API requests use HTTPS endpoints, refuse redirects, and disable
  response caches, cookies, and shared URL credential storage.
- OpenRouter receives audiobook chunks only when cloud transcription is chosen.
  Readwise receives the passages the user saves. Local transcription stays on
  the Mac.
- Book resources reject symbolic links and paths outside their package.
  EPUB archives are checked for traversal, symbolic links, and expansion
  limits before extraction.

GitHub Actions scans Git history for secrets and audits the support-site
lockfile on pushes and pull requests. The scanner and checkout action are
pinned, and the workflow has read-only repository permissions.

Stage the files you intend to publish, then run the local checks:

```sh
gitleaks git . --log-opts=--all --redact=100 --ignore-gitleaks-allow
gitleaks git . --pre-commit --staged --redact=100 --ignore-gitleaks-allow
cd SupportSite
npm audit --audit-level=low
```

The support-site overrides for `undici` 7.x and `fflate` 0.7.x select patched
versions while upstream tools retain older pins. Keep them until the upstream
dependency graph supplies patched versions itself.

If a real credential is exposed, revoke it with its provider and save a new
one in Clip. Removing it from the latest source does not remove it from Git
history. Do not paste the credential into a public issue when reporting it.
