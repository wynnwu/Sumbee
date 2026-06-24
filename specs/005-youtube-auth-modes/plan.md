# Implementation Plan: YouTube caption auth modes

**Spec**: `spec.md`  ·  **Decisions**: `research.md`  ·  **Tasks**: `tasks.md`

## Summary

Add a `YouTubeAuthMode` setting (Normal / Client tweak / Browser cookies: Chrome / Browser cookies:
Safari), thread it into the yt-dlp invocation, classify the bot-gate error distinctly with an
actionable message, and add a Settings card with truthful permission/privacy info. No new dependency.

## Architecture & touch points

```
Sources/SumbeeKit/
  Models/
    YouTubeAuthMode.swift     # NEW  enum + displayName + ytDlpArgs + usesBrowserCookies
    AppSettings.swift         # EDIT + youtubeAuthMode (property, init, CodingKeys, init(from:))
  Services/
    YouTubeService.swift      # EDIT fetchTranscript(authMode:); runFetch appends args;
                              #      + YouTubeError.signInRequired (+ message); classify detects it
    SummarizationEngine.swift # EDIT prepareYouTube passes settings.youtubeAuthMode
  Views/Settings/
    SettingsView.swift        # EDIT YouTubeSettingsSection: add the mode card + permission/privacy note
Tests/SumbeeKitTests/
    YouTubeServiceTests.swift # EDIT + classify("...not a bot...") == .signInRequired
    YouTubeAuthModeTests.swift# NEW  ytDlpArgs per mode; normal == []
```

No changes to persistence format beyond one tolerant field; no job-engine behavior change except the
new error landing in `fail(...)` (it is simply not in the retryable set).

## Component contracts

### `YouTubeAuthMode` (Models)

```swift
public enum YouTubeAuthMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case normal, clientTweak, cookiesChrome, cookiesSafari
    public var id: String { rawValue }
    public var displayName: String
    public var ytDlpArgs: [String]        // normal: []; clientTweak: --extractor-args ...;
                                          // cookies*: --cookies-from-browser chrome|safari
    public var usesBrowserCookies: Bool   // cookiesChrome || cookiesSafari
}
```

### `AppSettings`

- Add `public var youtubeAuthMode: YouTubeAuthMode` (default `.normal`) to the stored properties, the
  memberwise `init` (param + assignment), `CodingKeys`, and the field-tolerant `init(from:)`
  (`decodeIfPresent ... ?? d.youtubeAuthMode`). No schemaVersion bump needed (tolerant decode).

### `YouTubeService`

- `YouTubeError` gains `case signInRequired`; `userMessage`: actionable sentence (update yt-dlp in
  Settings ▸ YouTube, avoid VPNs, or turn on browser cookies, then Run queue).
- `classify`: add `if s.contains("not a bot") || s.contains("sign in to confirm") { return
  .signInRequired }` before the generic fallback.
- `fetchTranscript(_:language:ytDlp:authMode:)` (protocol + impl) and
  `runFetch(url:language:ytDlp:authMode:)` gain the param; `runFetch` does `args += authMode.ytDlpArgs`.

### `SummarizationEngine.prepareYouTube`

- `youtube.fetchTranscript(url, language: settings.captionLanguage, ytDlp: ytDlp, authMode:
  settings.youtubeAuthMode)`.

### `AppState+Jobs` (no code change required)

- The YouTubeError catch retries only `.network` / `.rateLimited`; `.signInRequired` falls to
  `fail(...)`, showing the actionable message (FR-058). Verified, not edited.

### `SettingsView` -> `YouTubeSettingsSection`

- New `SettingsCard("Access", systemImage: "person.badge.key.fill")` containing:
  - a short lead ("If YouTube asks you to confirm you're not a bot, first try Download / Update
    yt-dlp above; if it persists, choose how Sumbee authenticates");
  - a **flat** menu picker (same borderless `Menu` pattern as the bottom-bar model menu, to avoid the
    native bezel/shadow the Settings flattening removed) bound to `state.settings.youtubeAuthMode`,
    persisting on change;
  - a per-mode info block: Normal/Client tweak get a one-liner; the two cookie modes get the
    permission line (Keychain for Chrome / Full Disk Access for Safari) + the truthful privacy note.

## Testing

- **Unit**:
  - `YouTubeServiceTests`: `classify` of the real error string ("Sign in to confirm you're not a
    bot...") returns `.signInRequired`; a generic error still returns `.failed`.
  - `YouTubeAuthModeTests`: `.normal.ytDlpArgs == []`; `.cookiesChrome` / `.cookiesSafari` produce the
    `--cookies-from-browser` pair; `.clientTweak` produces an `--extractor-args` pair; all 4 modes are
    `CaseIterable` with stable raw values (persistence safety).
- **Build/verify**: `swift build` (0 warnings), `swift test` green. No app launch (Keychain). User
  validates the actual gate-bypass from the build.

## Risks & mitigations

- *Live YouTube untestable here*: logic is unit-tested; gate-bypass validated by the user. Client
  tweak value is a documented heuristic constant.
- *Cookie permission failures*: surface as normal fetch errors; the UI note sets expectations.

## Rollback

Self-contained: remove `YouTubeAuthMode.swift`, the one `AppSettings` field, the service param +
error case + classify line, the engine arg, and the Settings card. Tolerant decode means old/new
`config.json` round-trips either way.

## Docs to update on completion

- `docs/swift-macos-learnings.md` (#19: the bot gate + mitigations + cookie permissions).
- `CHANGELOG.md` (next/Unreleased) and a brief README YouTube note.
- Keep `specs/005-youtube-auth-modes/*` current (this set).
