# Research & Decisions: player client + auto-escalation

## D-A. Player client as its own enum + setting

`YouTubePlayerClient: String, Codable, CaseIterable, Sendable, Identifiable` with curated cases whose
**rawValue is the yt-dlp client name** (so it doubles as the persisted form and the arg value):
`android` (default/preselected), `web_safari`, `tv`, `ios`, `mweb`. Stored on
`AppSettings.youtubePlayerClient` (field-tolerant, default `.android`).

`YouTubeAuthMode.ytDlpArgs` becomes a function taking the player client:
`ytDlpArgs(playerClient:)` -> clientTweak yields
`["--extractor-args", "youtube:player_client=\(playerClient.rawValue)"]`; other modes ignore it.
(005's `var ytDlpArgs` is replaced; its tests update to the new signature.)

## D-B. The escalation is a per-job, one-shot auth override

Add `Job.youtubeAuthOverride: YouTubeAuthMode?`. In `runJob`, the per-run settings snapshot applies
it: `var s = self.settings; if let o = job.youtubeAuthOverride { s.youtubeAuthMode = o }`. The bot
gate fails during the **prepare/fetch** step *before* `prepared` is cached, so simply re-queuing the
job re-fetches with the new args (no special re-fetch plumbing). Regenerate re-fetches via
`prepareFromArchive -> prepareYouTube`, so it inherits the same behavior.

## D-C. Decision logic is a pure, testable function

The "what to do when this mode still hits the gate" decision lives on the enum so it can be
unit-tested without the async job queue:

```swift
enum GateOutcome: Equatable { case escalateToClientTweak, adviseCookies, adviseCookieTrouble }
var gateOutcome: GateOutcome {
    switch self {
    case .normal:                     return .escalateToClientTweak
    case .clientTweak:                return .adviseCookies
    case .cookiesChrome, .cookiesSafari: return .adviseCookieTrouble
    }
}
```

`runJob`'s YouTubeError catch routes `.signInRequired` to `handleSignInGate(job)`, which switches on
`(job.youtubeAuthOverride ?? settings.youtubeAuthMode).gateOutcome`:
- `escalateToClientTweak`: toast ("trying a different player automatically"), set
  `youtubeAuthOverride = .clientTweak`, clear `prepared`, set phase `.queued`, `startProcessing()`.
- `adviseCookies`: **clear** `youtubeAuthOverride` (so a later Run queue honors the current setting),
  then `fail(...)` with the switch-to-cookies message.
- `adviseCookieTrouble`: `fail(...)` with the cookie-trouble message.

One-shot is guaranteed: Normal -> (override set) clientTweak -> adviseCookies. No loop. A non-gate
error on the retry uses the existing network/rate-limit/backoff branches unchanged.

## D-D. UI

In `YouTubeSettingsSection`, when the mode is Client tweak, show a **Player** flat-menu picker bound
to `settings.youtubePlayerClient` (same borderless style as the mode menu). The Client-tweak info
line mentions the chosen player. Cookie-mode notes are unchanged from 005.

## Risks

- **Can't test live YouTube here**: the gate-decision function and the player-client args are
  unit-tested; the escalation wiring is reviewed (adversarially) and validated by the user from the
  build. The player client remains a heuristic; cookies stay the reliable path.
- **Override leaking across Run queue**: mitigated by clearing the override on the `adviseCookies`
  terminal (D-C), so switching to cookies + Run queue works.
- **Re-queue racing the running task**: `handleSignInGate` runs inside `runJob`'s catch; it sets the
  job `.queued` and returns, and `processQueue`'s loop re-selects it. `startProcessing()` is a no-op
  while the queue task is alive (guard), which is correct - the loop picks it up next iteration.
