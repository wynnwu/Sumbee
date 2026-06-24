# Tasks: YouTube caption auth modes

**Input**: `spec.md`, `research.md`, `plan.md`
**Tests**: Arg-building and classification are unit-tested; the actual gate-bypass is validated by the
user from the build (live YouTube + IP-specific; no app launch here, Keychain/learnings #3/#4).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: parallelizable (different files)
- **[Story]**: US1 (clear failure), US2 (mode picker), US3 (cookie permission/privacy info)

---

## Phase 1: Model + settings

- [x] T001 [P][US2] `Models/YouTubeAuthMode.swift`: enum `normal/clientTweak/cookiesChrome/cookiesSafari`
      (`String, Codable, CaseIterable, Sendable, Identifiable`) with `displayName`, `ytDlpArgs`,
      `usesBrowserCookies`. Normal -> `[]`; clientTweak -> `--extractor-args youtube:player_client=android`;
      cookies -> `--cookies-from-browser chrome|safari`.
- [x] T002 [US2] `Models/AppSettings.swift`: add `youtubeAuthMode: YouTubeAuthMode = .normal` to
      properties, memberwise `init`, `CodingKeys`, and field-tolerant `init(from:)`.

## Phase 2: Service

- [x] T003 [US1] `Services/YouTubeService.swift`: add `YouTubeError.signInRequired` + actionable
      `userMessage`; `classify` returns it for "not a bot" / "sign in to confirm" (before fallback).
- [x] T004 [US2] `Services/YouTubeService.swift`: add `authMode` to the `fetchTranscript` protocol
      method + impl and to `runFetch`; `runFetch` appends `authMode.ytDlpArgs` to the args.
- [x] T005 [US2] `Services/SummarizationEngine.swift`: `prepareYouTube` passes
      `authMode: settings.youtubeAuthMode`.

## Phase 3: Settings UI

- [x] T006 [US2][US3] `Views/Settings/SettingsView.swift` (`YouTubeSettingsSection`): add an "Access"
      card with a flat menu picker bound to `state.settings.youtubeAuthMode` (persist on change) and a
      lead pointing at Update yt-dlp.
- [x] T007 [US3] Same card: per-mode info; cookie modes show the permission line (Chrome: Keychain
      prompt; Safari: Full Disk Access) and the truthful privacy note (only YouTube cookies used/sent,
      only to YouTube; Sumbee stores none).

## Phase 4: Verify & document

- [x] T008 [US1] `Tests/SumbeeKitTests/YouTubeServiceTests.swift`: classify of the real bot-gate
      string == `.signInRequired`; a generic error still == `.failed`.
- [x] T009 [P][US2] `Tests/SumbeeKitTests/YouTubeAuthModeTests.swift`: `ytDlpArgs` per mode
      (normal == []; cookie + extractor-arg pairs); 4 cases with stable raw values.
- [x] T010 `swift build` clean (0 warnings) + `swift test` green; confirm no new dependency.
- [x] T011 [P] `docs/swift-macos-learnings.md` #19 (bot gate + mitigations + cookie permissions);
      `CHANGELOG.md` (next/Unreleased); brief README YouTube note.

---

**Checkpoint**: bot-gate failures show an actionable message and don't auto-retry; Settings ▸ YouTube
offers the four auth modes with truthful cookie info; Normal is unchanged; build + tests green; PR
opened for user validation. Commit/push/PR only when asked (the user said "Implement").
