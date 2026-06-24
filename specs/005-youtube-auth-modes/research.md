# Research & Decisions: YouTube caption auth modes

Decisions are lettered `D-A...` to stay local to this feature. Web research (June 2026):
[yt-dlp FAQ](https://github.com/yt-dlp/yt-dlp/wiki/FAQ),
[issue #12264 (cookies/proxies)](https://github.com/yt-dlp/yt-dlp/issues/12264),
[6 ways to get YouTube cookies in 2026](https://dev.to/osovsky/6-ways-to-get-youtube-cookies-for-yt-dlp-in-2026-only-1-works-2cnb).

## D-A. The error and its real causes

"Sign in to confirm you're not a bot" is an anti-bot gate keyed on IP reputation and yt-dlp
freshness. Top remedies, in order of reliability:
1. **Update yt-dlp** (stale versions trip it via signature/JS extraction). Already a one-click action
   in Settings; remains the first thing to try.
2. **Avoid VPN / datacenter IPs.**
3. **`--cookies-from-browser`** (send your logged-in session) - the reliable fix.
4. **`--extractor-args "youtube:player_client=..."`** - a no-login lever that often slips past the
   gate for public videos, but a moving target.

## D-B. Model: a single `YouTubeAuthMode` enum

```swift
public enum YouTubeAuthMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case normal, clientTweak, cookiesChrome, cookiesSafari
    var displayName: String { ... }      // "Normal", "Client tweak", "Browser cookies: Chrome/Safari"
    var ytDlpArgs: [String] { ... }      // the extra args this mode contributes
    var usesBrowserCookies: Bool { ... } // chrome || safari (drives the permission note)
}
```

Lives in `Models/` (like `OutputFormat`) so `AppSettings` can hold it and the Settings view + the
service can both read it. Persisted on `AppSettings.youtubeAuthMode` (field-tolerant, default
`.normal`).

- `ytDlpArgs`:
  - `.normal` -> `[]` (SC-004: byte-for-byte unchanged invocation).
  - `.clientTweak` -> `["--extractor-args", "youtube:player_client=android"]`. `android` is the most
    widely cited no-login client; it is a single, documented heuristic constant (easy to retune) -
    we deliberately avoid a long client list so one renamed client can't fail the whole fetch.
  - `.cookiesChrome` -> `["--cookies-from-browser", "chrome"]`.
  - `.cookiesSafari` -> `["--cookies-from-browser", "safari"]`.
- Cookie modes deliberately do **not** also force a `player_client`: the default client honors
  cookies, whereas some clients (e.g. `ios`) ignore them (the documented "cookie trap").

## D-C. Permissions and the privacy note (must be truthful)

- **Chrome**: yt-dlp reads `.../Google/Chrome/<profile>/Cookies` (SQLite) and decrypts it with the
  "Chrome Safe Storage" key from the **macOS Keychain** -> a one-time Keychain access prompt.
- **Safari**: cookies live in a **TCC-protected** container, so the app spawning yt-dlp (Sumbee)
  needs **Full Disk Access** (System Settings ▸ Privacy & Security ▸ Full Disk Access). For ad-hoc
  builds, FDA is tied to the unstable identity and can reset on rebuild (learnings #3).
- **Truthfulness**: `--cookies-from-browser` loads the browser's whole cookie jar; yt-dlp then sends
  only cookies relevant to the request (YouTube) to YouTube. So the copy says "only your YouTube
  cookies are used and sent, only to YouTube; Sumbee stores none" - NOT "Sumbee reads only the
  YouTube cookie" (which would be false at the file level). This nuance is surfaced to the user.

## D-D. Classification + retry policy

`classify` gains, before the generic fallback:
```swift
if s.contains("not a bot") || s.contains("sign in to confirm") { return .signInRequired }
```
`YouTubeError.signInRequired.userMessage` is actionable (update yt-dlp, avoid VPNs, enable browser
cookies in Settings ▸ YouTube). It is **not** added to the retryable set in `AppState+Jobs` (the
YouTubeError catch retries only `.network` / `.rateLimited`), so it lands in `fail(...)` with the
clear message - no pointless backoff loop.

## D-E. Threading the setting to yt-dlp

`fetchTranscript` and `runFetch` take a `YouTubeAuthMode`; `runFetch` appends `authMode.ytDlpArgs`
to the existing arg list. The only caller is `SummarizationEngine.prepareYouTube`, which already has
`settings` in scope (passes `settings.youtubeAuthMode`). There are no `YouTubeServicing` mocks in the
test suite, so the protocol change touches only the real impl + the one call site.

## Risks

- **Can't test live YouTube from here** (and behavior is IP-specific). The arg-building and
  classification are unit-tested; the actual gate-bypass is validated by the user from the build
  ("you can validate the code in the repo"). The client-tweak value is an explicit heuristic.
- **Cookie reading permissions** can fail on a given machine (no Chrome, encrypted store, missing
  FDA); that surfaces as a normal fetch failure with its message. Documented in the UI note and
  learnings #19.
