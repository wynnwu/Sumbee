# Tasks: player client + auto-escalation

**Input**: `spec.md`, `research.md`, `plan.md`
**Tests**: gate-decision + player-client args are unit-tested; the async escalation wiring is reviewed
(adversarial) and validated by the user from the build (live YouTube is IP-specific; no app launch).

## Phase 1: Model + settings

- [x] T001 [P][US1] `Models/YouTubePlayerClient.swift`: enum, rawValue == yt-dlp client name
      (`android`/`web_safari`/`tv`/`ios`/`mweb`), `displayName`, `Identifiable`/`CaseIterable`/`Codable`.
- [x] T002 [US1][US2] `Models/YouTubeAuthMode.swift`: replace `var ytDlpArgs` with
      `func ytDlpArgs(playerClient:)`; add `GateOutcome` + `var gateOutcome`.
- [x] T003 [US1] `Models/AppSettings.swift`: add `youtubePlayerClient: YouTubePlayerClient = .android`
      (property, init, CodingKeys, field-tolerant `init(from:)`).
- [x] T004 [US2] `Models/Job.swift`: add `var youtubeAuthOverride: YouTubeAuthMode? = nil`.

## Phase 2: Service + engine

- [x] T005 [US1] `Services/YouTubeService.swift`: `fetchTranscript`/`runFetch` take
      `playerClient: YouTubePlayerClient`; `runFetch` appends `authMode.ytDlpArgs(playerClient:)`.
- [x] T006 [US1] `Services/SummarizationEngine.swift`: `prepareYouTube` passes
      `playerClient: settings.youtubePlayerClient`.

## Phase 3: Escalation

- [x] T007 [US2][US3] `State/AppState+Jobs.swift`: `runJob` applies `job.youtubeAuthOverride` to the
      per-run settings snapshot; YouTubeError catch routes `.signInRequired` to `handleSignInGate`.
- [x] T008 [US2][US3] `State/AppState+Jobs.swift`: add `handleSignInGate(_:)` per plan (escalate /
      advise-cookies + clear override / advise-cookie-trouble).

## Phase 4: UI

- [x] T009 [US1] `Views/Settings/SettingsView.swift`: when mode is Client tweak, show a flat **Player**
      menu bound to `settings.youtubePlayerClient` (persist on change); name the player in the info line.

## Phase 5: Verify & document

- [x] T010 [P] `Tests/SumbeeKitTests/YouTubeGateTests.swift`: `gateOutcome` per mode; player-client
      args + rawValues. Update `YouTubeAuthModeTests.swift` to the new `ytDlpArgs(playerClient:)`.
- [x] T011 `swift build` clean (0 warnings) + `swift test` green; confirm no new dependency.
- [x] T012 Adversarial review (workflow) of the escalation state machine: loops, override-clear,
      wrong-job escalation, cancel/Run-queue interaction, regenerate path. Fix findings.
- [x] T013 [P] `CHANGELOG.md` (Unreleased) + brief README note.

---

**Checkpoint**: player client selectable; Normal-mode gate failures auto-retry once with Client tweak
then guide to cookies, no loops; build + tests green; PR for user validation. Commit/push/PR only when
asked (the user said implement).
