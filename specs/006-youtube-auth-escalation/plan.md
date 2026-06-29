# Implementation Plan: player client + auto-escalation

**Spec**: `spec.md`  ·  **Decisions**: `research.md`  ·  **Tasks**: `tasks.md`

## Touch points

```
Sources/SumbeeKit/
  Models/
    YouTubePlayerClient.swift   # NEW  enum (rawValue == yt-dlp client name) + displayName
    YouTubeAuthMode.swift       # EDIT ytDlpArgs -> ytDlpArgs(playerClient:); + GateOutcome + gateOutcome
    AppSettings.swift           # EDIT + youtubePlayerClient (property, init, CodingKeys, init(from:))
    Job.swift                   # EDIT + youtubeAuthOverride: YouTubeAuthMode?
  Services/
    YouTubeService.swift        # EDIT fetchTranscript/runFetch take playerClient; args use it
    SummarizationEngine.swift   # EDIT prepareYouTube passes settings.youtubePlayerClient
  State/
    AppState+Jobs.swift         # EDIT runJob applies job.youtubeAuthOverride; .signInRequired ->
                                #      handleSignInGate (escalate / advise) per GateOutcome
  Views/Settings/
    SettingsView.swift          # EDIT clientTweak shows a Player dropdown + names the player
Tests/SumbeeKitTests/
    YouTubeAuthModeTests.swift  # EDIT new ytDlpArgs(playerClient:) signature
    YouTubeGateTests.swift      # NEW  gateOutcome per mode; player-client args/rawValues
```

## Key code

### `handleSignInGate` (AppState+Jobs)

```swift
private func handleSignInGate(_ job: Job) {
    let mode = job.youtubeAuthOverride ?? settings.youtubeAuthMode
    switch mode.gateOutcome {
    case .escalateToClientTweak:
        present(.info, "YouTube asked to confirm you’re not a bot. Trying a different player automatically…")
        updateJob(job.id) {
            $0.youtubeAuthOverride = .clientTweak
            $0.prepared = nil
            $0.nextRetryAt = nil
            $0.phase = .queued
        }
        startProcessing()
    case .adviseCookies:
        updateJob(job.id) { $0.youtubeAuthOverride = nil }   // later Run queue honors current setting
        fail(job.id, "A different player still didn’t get past YouTube’s check. In Settings ▸ YouTube, switch to Browser cookies (Chrome or Safari) to use your login, then Run queue.")
    case .adviseCookieTrouble:
        fail(job.id, "Browser cookies didn’t get past YouTube’s check. Make sure you’re signed in to YouTube in that browser (and grant the permission Sumbee asks for), or update yt-dlp, then Run queue.")
    }
}
```

### `runJob` snapshot + catch

- Snapshot: `var settings = self.settings; if let o = job.youtubeAuthOverride { settings.youtubeAuthMode = o }`.
- Catch: replace the `else { fail(...) }` of the YouTubeError arm so `.signInRequired ->
  handleSignInGate(job)`, other non-retryable YouTube errors still `fail(...)`.

## Testing

- **Unit**: `YouTubeGateTests` - `gateOutcome` for each of the 4 modes; `ytDlpArgs(playerClient:)` for
  each mode (clientTweak embeds the rawValue; cookies/normal unchanged); `YouTubePlayerClient`
  rawValues stable + count.
- **Build/verify**: `swift build` (0 warnings), `swift test` green. The escalation wiring is reviewed
  (adversarial workflow) since it is async/stateful; the user validates the live behavior.

## Risks & rollback

- Risks per research D-C/D (one-shot, override-clear, re-queue race). Rollback: remove the override
  field + handleSignInGate + the new enum/setting; revert the args function to a constant.

## Docs on completion

`CHANGELOG.md` (Unreleased), brief README note, keep `specs/006-*` current. (learnings #19 already
covers the gate; no new learning needed.)
