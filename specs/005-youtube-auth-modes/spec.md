# Feature Specification: YouTube caption auth modes (anti-bot gate)

**Feature Branch**: `005-youtube-auth-modes`

**Created**: 2026-06-25

**Status**: Draft

**Input**: User report: caption fetch failed with `ERROR: [youtube] <id>: Sign in to confirm you're
not a bot. Use --cookies-from-browser or --cooki...`. User decision: "Add options for normal, client
tweak, or browser cookie via Chrome, browser cookie via Safari. Make a nice info for the browser
cookie about how if you select it extra permissions are necessary, but we will only read the YouTube
cookie."

## Background

YouTube increasingly gates caption/metadata fetches behind a "Sign in to confirm you're not a bot"
check, triggered by IP reputation (VPNs / datacenter IPs, sometimes plain residential bad luck) and,
very often, an **out-of-date yt-dlp**. This is distinct from the HTTP 429 rate-limit handled in
0.2.7. Today `YouTubeService.classify` has no case for it, so it falls through to the generic
`.failed(...)` branch: the user sees the raw error with no guidance, and (because `.failed` is not
retryable) the job just fails.

yt-dlp's own remedy is authentication: `--cookies-from-browser <browser>` (use your logged-in
session) or `--cookies <file>`. A lighter, no-login lever is `--extractor-args
"youtube:player_client=..."`, which selects non-web player clients that the gate often checks less
aggressively for public videos (a heuristic YouTube changes over time). Updating yt-dlp frequently
resolves it on its own.

## Clarifications

### Session 2026-06-25

- Q: Which mitigations should Sumbee offer? -> A: A **mode picker** in Settings ▸ YouTube with four
  choices: **Normal** (today's behavior), **Client tweak** (no-login `player_client` override),
  **Browser cookies: Chrome**, **Browser cookies: Safari**.
- Q: Firefox / cookies.txt? -> A: **Out of scope** for now (user chose Chrome and Safari). Firefox,
  other browsers, and a manual cookies.txt path can be added later.
- Q: Privacy / permissions messaging for the cookie modes? -> A: Show a clear, **truthful** note:
  the extra macOS permission each needs, and that only the user's YouTube cookies are sent (only to
  YouTube). yt-dlp technically reads the browser's cookie store, so the copy must not claim Sumbee
  reads "only the YouTube cookie" at the file level; it claims only YouTube cookies are *used/sent*.
- Q: Should the bot-gate failure auto-retry? -> A: **No.** It needs a user action (update yt-dlp,
  change mode, drop the VPN). Surface a clear, actionable message; the user retries via "Run queue".

## User Scenarios & Testing

### User Story 1 - Understand the failure (Priority: P1)

**Why**: Today the bot-gate failure is an opaque raw dump.

**Acceptance**:
1. **Given** yt-dlp returns "Sign in to confirm you're not a bot", **when** the job fails, **then**
   the toast/message is a distinct, actionable sentence (update yt-dlp, avoid VPNs, or enable browser
   cookies in Settings), not the raw stderr.
2. **Given** that failure, **then** the job is **not** auto-retried (it needs user action); the user
   can retry with "Run queue" after changing something.

### User Story 2 - Choose how YouTube authenticates (Priority: P1)

**Why**: The reliable fix is cookies; a lighter fix is a client tweak. The user picks the tradeoff.

**Acceptance**:
1. **Given** Settings ▸ YouTube, **then** there is a mode picker: Normal, Client tweak, Browser
   cookies: Chrome, Browser cookies: Safari. The choice persists across launches; default is Normal.
2. **Given** Normal, **then** caption fetches behave exactly as today (no extra yt-dlp args).
3. **Given** Client tweak, **then** fetches pass a no-login `player_client` override (no cookies).
4. **Given** Browser cookies: Chrome / Safari, **then** fetches pass `--cookies-from-browser
   chrome` / `safari`.

### User Story 3 - Know the cost of cookie modes (Priority: P1)

**Why**: Reading browser cookies needs OS permissions and is privacy-sensitive; the user must
understand it before opting in.

**Acceptance**:
1. **Given** Browser cookies: Chrome is selected, **then** the UI explains macOS will prompt once for
   **Keychain** access (Chrome Safe Storage), and that only YouTube cookies are sent, only to YouTube.
2. **Given** Browser cookies: Safari is selected, **then** the UI explains it needs **Full Disk
   Access** for Sumbee (System Settings ▸ Privacy & Security), with the same privacy note.
3. The note is **truthful**: it does not claim Sumbee reads only the YouTube cookie from disk (yt-dlp
   reads the browser cookie store); it states only YouTube cookies are used and sent, only to YouTube,
   and Sumbee stores none.

### Edge Cases

- **Ad-hoc build + Safari Full Disk Access**: FDA grants are tied to the (unstable) ad-hoc identity
  and can reset on rebuild (learnings #3); note that re-granting may be needed after an update.
- **Chrome cookie encryption / no Chrome installed**: yt-dlp may still error; that surfaces as a
  normal fetch failure with its message (not special-cased).
- **player_client heuristic goes stale**: the client tweak may stop helping as YouTube changes; the
  value is a single, documented constant that is easy to update. Cookies remain the reliable path.
- **Regenerate** of a YouTube summary uses the same setting (it re-fetches captions).

## Requirements

### Functional Requirements

- **FR-058**: A "Sign in to confirm you're not a bot" failure MUST be classified distinctly
  (`YouTubeError.signInRequired`) with an actionable message, and MUST NOT auto-retry.
- **FR-059**: Settings ▸ YouTube MUST offer a persisted caption-fetch auth mode with four options:
  Normal, Client tweak, Browser cookies: Chrome, Browser cookies: Safari. Default Normal;
  field-tolerant persistence (older configs decode unchanged).
- **FR-060**: Normal MUST add no yt-dlp args (unchanged behavior). Client tweak MUST add a no-login
  `--extractor-args "youtube:player_client=..."`. The cookie modes MUST add `--cookies-from-browser
  chrome` / `--cookies-from-browser safari`.
- **FR-061**: The cookie modes MUST show, in Settings, the extra permission each needs (Chrome:
  Keychain prompt; Safari: Full Disk Access) and a truthful privacy note (only YouTube cookies are
  used and sent, only to YouTube; Sumbee stores none).
- **FR-062**: No new third-party dependency. Normal-mode behavior and all non-YouTube features are
  unchanged.

### Out of scope (this feature)

- Firefox / Brave / Edge cookie sources and a manual cookies.txt path (could follow).
- Automatic fallback across modes, or auto-detecting which browser the user is signed into.
- Bundling/auto-updating yt-dlp differently (the existing "Download / Update yt-dlp" stays the first
  thing to try).

## Success Criteria

- **SC-001**: The reported error now yields a clear, actionable message and does not silently retry.
- **SC-002**: A user can switch to Browser cookies: Chrome or Safari, understand the permission and
  privacy implications from the UI, and (with a signed-in browser) fetch captions that were gated.
- **SC-003**: `swift build` clean (0 warnings), `swift test` green (incl. a classify regression test
  for the exact error and a test of each mode's yt-dlp args). No new dependency.
- **SC-004**: Normal mode is byte-for-byte the same yt-dlp invocation as before this feature.
