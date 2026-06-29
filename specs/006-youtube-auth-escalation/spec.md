# Feature Specification: Selectable player client + auto-escalation for the YouTube bot gate

**Feature Branch**: `006-youtube-auth-escalation`

**Created**: 2026-06-25

**Status**: Draft

**Input**: User: "Make `player_client` a selectable drop-down list in the Client tweak mode with a
preferred preselected. Also, if it runs into this [bot-gate] error on no-hacks (Normal) mode, pop a
toast that it will automatically try to switch to player_client mode and try again. If that fails,
ask the user to set a YouTube cookie mode."

## Background

005 added `YouTubeAuthMode` (Normal / Client tweak / Browser cookies: Chrome / Safari). Client tweak
hard-codes `--extractor-args youtube:player_client=android`. This feature (1) makes that client a
user-selectable dropdown, and (2) adds a one-shot auto-escalation: when a fetch in Normal mode hits
the "Sign in to confirm you're not a bot" gate, the app automatically retries that job once with
Client tweak, and if that still fails, guides the user to Browser cookies.

## Clarifications

### Session 2026-06-25

- Q: Which player clients in the dropdown? -> A: A curated list of no-login-friendly yt-dlp clients:
  **Android (recommended/preselected)**, Safari (web), TV, iOS, Mobile web. Persisted; default
  Android.
- Q: When does auto-escalation trigger? -> A: Only on the **bot gate** (`signInRequired`), only when
  the job's effective mode is **Normal**, exactly **once** per job. It switches that job to Client
  tweak (using the selected player client) and re-runs it.
- Q: What if the escalated Client tweak retry also fails the gate? -> A: Fail the job with an
  actionable message asking the user to switch to **Browser cookies** (Chrome/Safari) and Run queue,
  and clear the per-job override so a later Run queue honors the user's current setting.
- Q: What if a cookie mode still hits the gate? -> A: Fail with guidance (sign in to YouTube in that
  browser, grant the permission, or update yt-dlp). No further auto-escalation.
- Q: Geek mode? -> A: The geek-mode preview fetches before sending; a gate failure there surfaces the
  error as today (no auto-escalation in the preview path). Out of scope.

## User Scenarios & Testing

### User Story 1 - Pick the player client (Priority: P2)

**Acceptance**:
1. **Given** Client tweak is selected in Settings ▸ YouTube, **then** a **Player** dropdown appears
   with Android (preselected), Safari (web), TV, iOS, Mobile web; the choice persists.
2. **Given** a chosen player, **then** Client-tweak fetches pass
   `--extractor-args youtube:player_client=<chosen>`.

### User Story 2 - Auto-escalate from Normal on the bot gate (Priority: P1)

**Acceptance**:
1. **Given** a YouTube job in Normal mode that fails with the bot gate, **then** a toast says the app
   will try a different player automatically, the job switches to Client tweak (selected player), and
   it re-runs once.
2. **Given** the escalated retry succeeds, **then** the summary is produced normally.
3. **Given** the escalated retry still fails the gate, **then** the job fails with a message telling
   the user to switch to Browser cookies (Chrome/Safari) and Run queue; escalation does not loop.

### User Story 3 - Guide to cookies when needed (Priority: P1)

**Acceptance**:
1. **Given** the escalation chain has failed, **when** the user switches Settings ▸ YouTube to a
   cookie mode and clicks Run queue, **then** the job uses cookies (the per-job override no longer
   forces Client tweak).
2. **Given** a cookie mode still hits the gate, **then** the failure message guides the user (sign in
   to YouTube in that browser / grant permission / update yt-dlp).

### Edge Cases

- Escalation is **one-shot per job** (driven by a per-job override); no infinite loops.
- A non-gate error on the escalated retry (e.g. network) follows the normal retry/backoff path.
- Cancel during/after escalation behaves like any cancel (cancellation wins).
- Regenerating a YouTube summary re-fetches via the same path, so it escalates the same way.
- Manually choosing Client tweak (not via escalation) and hitting the gate goes straight to the
  "switch to cookies" guidance (no escalation from an explicit Client-tweak choice).

## Requirements

### Functional Requirements

- **FR-063**: Client tweak mode MUST expose a persisted, curated player-client dropdown (Android
  preselected, plus Safari-web/TV/iOS/Mobile-web); the chosen client MUST be what
  `--extractor-args youtube:player_client=` uses.
- **FR-064**: On a bot-gate failure of a YouTube job whose effective mode is Normal, the app MUST
  toast that it will try a different player automatically, switch that job to Client tweak (selected
  player), and re-run it exactly once.
- **FR-065**: If the auto-escalated Client-tweak retry still hits the gate, the app MUST fail the job
  with a message to switch to Browser cookies and Run queue, and MUST clear the per-job override so a
  later Run queue honors the user's current setting.
- **FR-066**: If a cookie mode still hits the gate, the app MUST fail with actionable guidance and
  MUST NOT auto-escalate further.
- **FR-067**: Escalation MUST be one-shot per job (no loops), MUST apply to YouTube fetches including
  Regenerate, and MUST NOT change Normal-mode behavior except on the gate failure.

### Out of scope

- Auto-escalation inside the geek-mode preview path.
- Trying multiple player clients in sequence automatically.
- Auto-switching to cookie modes without user action (cookies need a deliberate opt-in / permission).

## Success Criteria

- **SC-001**: A Normal-mode bot-gate failure visibly auto-retries once with Client tweak and, if that
  fails, lands on clear cookie guidance, with no retry loop.
- **SC-002**: The player client is selectable and persists; Normal mode is unchanged otherwise.
- **SC-003**: `swift build` clean (0 warnings); `swift test` green incl. unit tests for the
  gate-resolution decision and the player-client args. No new dependency.
