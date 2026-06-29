# Swift / macOS learnings (hard-won)

Real bugs we hit building Sumbee (and a sibling SwiftPM menu-bar app) and the rules that prevent them.
Read before touching persistence, permissions, the library list, fonts, icons, shell scripts, or any
AppKit/menu-bar/animation/vibrancy work. Each entry: **Symptom → Cause → Rule.**

## Persistence

### 1. Adding a field to a `Codable` settings struct silently wiped ALL settings
- **Symptom**: after adding a property, users' saved config reset to defaults.
- **Cause**: synthesized `Codable` decoding **fails entirely** if a key is missing, and our loader
  fell back to `AppSettings()` on any decode error → total reset.
- **Rule**: settings use a **field-tolerant** `init(from:)`; every key is
  `decodeIfPresent(...) ?? default`. Adding a field must never fail to decode an older file.
  (See `AppSettings.swift` / research D15.) Add new fields to: properties, memberwise `init`,
  `CodingKeys`, **and** `init(from:)`.

## Permissions, TCC & signing

### 2. `~/Documents` (and Desktop/Downloads) are TCC-protected: "Reveal in Finder" silently opened Home
- **Symptom**: reveal "worked" (`exists=true`, `open` returned 0) but Finder showed the home folder.
- **Cause**: driving Finder to open a path inside a TCC-protected folder from an **unsigned/ad-hoc**
  app is silently refused; Finder falls back to Home. Direct file *reads* still worked, which masked it.
- **Rule**: keep app-owned data **out of `~/Documents`**. Sumbee's default library is `~/Sumbee Summaries`
  (a plain home folder, no TCC gate). For "reveal", opening a non-protected folder works reliably.

### 3. Ad-hoc signing has no stable identity → permissions reset every rebuild
- **Symptom**: TCC grants and Keychain access needed re-approving after each `swift build`/bundle.
- **Cause**: ad-hoc signatures have no stable *designated requirement*, so macOS treats each build as
  a new app for TCC and Keychain ACLs.
- **Rule**: expect re-granting in dev; don't design flows that assume persistent grants across
  rebuilds. The real fix is a Developer-ID-signed + notarized build.

### 4. Reading a Keychain item created under a *different* identity blocks on a prompt (hung headless)
- **Symptom**: smoke run hung (watchdog SIGKILL / exit 137) after adding a "migrate old API key" step.
- **Cause**: reading a Keychain item whose ACL belongs to a prior (ad-hoc) identity triggers an
  **interactive** "allow access" dialog, which blocks, and can't be answered headlessly.
- **Rule**: don't auto-read Keychain items created by a different code identity. Prefer asking the
  user to re-enter, or migrate only with explicit UI.

### 5. Diagnose silent native failures by surfacing state, not guessing
- We burned several rounds guessing at the reveal bug. What ended it: a toast printing
  `exists=…`, the `open` exit code, and using `selectFile` (returns `Bool`) instead of
  `activateFileViewerSelecting` (returns `Void`).
- **Rule**: when an AppKit call "does nothing", surface its return value / preconditions to the UI
  (temporarily) before changing the approach.

## SwiftUI ↔ AppKit interop

### 6. `.onDrag` on a `List` row breaks click-to-select
- **Symptom**: clicking a library row didn't select it (felt like a mouse-sensitivity issue); arrow
  keys still worked.
- **Cause**: `.onDrag` installs a drag gesture that swallows the row's mouse-down, so `List`'s
  click-selection never fires. Keyboard nav bypasses the gesture, hence arrows worked.
- **Rule**: don't use `.onDrag` on selectable `List` rows. Use **`.draggable(_:)`** (designed to
  coexist with selection) or back the list with an AppKit `NSTableView` for exact Finder behavior
  (click selects, press-and-drag exports, keyboard nav free).

### 7. A drag source over a movable window drags the *window*
- **Symptom**: dragging a Text in the preview moved the whole window instead of starting a file drag.
- **Cause**: the window is `isMovableByWindowBackground = true`; background-hosted views forward the
  drag to the window.
- **Rule**: don't place drag sources on views sitting on a movable window background. Put drag on
  list rows / dedicated controls, not free-floating background text.

### 8. Window activation flags can surface the wrong window
- **Symptom**: after revealing, Finder came forward showing a stale Home window.
- **Cause**: `NSRunningApplication.activate(options: [.activateAllWindows])` raises **all** of the
  app's windows, so a pre-existing window can land on top of the just-revealed one.
- **Rule**: prefer activating just the target window; avoid `.activateAllWindows` when you care
  which window ends up frontmost.

### 9. `TextEditor` has an opaque background
- **Symptom**: a `TextEditor` over a material looked like a flat white/gray box.
- **Rule**: add `.scrollContentBackground(.hidden)` so the material/background shows through.

### 18. A `WKWebView` loaded off the main thread silently renders a blank page
- **Symptom**: the *first* HTML summary opened in a session showed a blank white page; the next one
  rendered fine, and returning to the first then worked too (100% repro).
- **Cause**: the in-app HTML viewer gated its first `loadHTMLString` behind a one-time
  `WKContentRuleListStore.compileContentRuleList(...)` (the remote-load privacy block). That
  completion handler is **not guaranteed to run on the main thread**, so the first document's only
  load (and the `WKUserContentController.add`) executed off-main. `WKWebView` is main-thread-only;
  off-main calls are undefined behavior and here just painted nothing. Every later load came from the
  SwiftUI `updateNSView` pass (main thread) once the rule list was cached, hence "only the first".
- **Rule**: treat every `WKWebView`/`WKUserContentController` mutation (including `loadHTMLString`)
  as main-thread-only. Any async completion that drives them (rule-list compile, file read, network)
  must `DispatchQueue.main.async` before touching WebKit. If you gate the first paint on async setup
  for a good reason (we gate on the remote-load block for privacy), keep the gate but make the
  resumed load run on main. Verified by independent adversarial review: the naive fix (load eagerly,
  ungated) reintroduced a privacy hole by painting before the block installed.

## Layout & typography

### 10. `.dynamicTypeSize` barely scales macOS's built-in text styles
- **Symptom**: "make the fonts bigger" via `.dynamicTypeSize(.xLarge)` did almost nothing.
- **Cause**: on macOS, Dynamic Type has little effect on the standard text styles.
- **Rule**: use **explicit point sizes** via a small shared font-token set (`Font.uiTitle/uiBody/…`)
  rather than relying on Dynamic Type. Fixed `.system(size:)` fonts don't scale with Dynamic Type
  either; that's a feature here.

### 11. `LazyVGrid(.adaptive)` inside `HSplitView` caused layout-cycle hangs
- **Rule**: avoid `.adaptive` grid columns inside `HSplitView`; use fixed/flexible columns.
  (Research D10.)

## Icons, build & tooling

### 12. Build `.icns` with `iconutil`, not by hand
- **Symptom**: the app icon rendered as colored garbage in Finder.
- **Cause**: the `.icns` was a single malformed `icp4` entry (a 1024px image under a 16×16 tag).
- **Rule**: produce icons with `iconutil -c icns Name.iconset` from a complete `.iconset`
  (16…1024, @1x/@2x). Validate by extracting back: `iconutil -c iconset Name.icns`. For the two
  smallest sizes, ship a simplified mark (we use bee-only); fine detail is illegible at 16/32 px.

### 13. macOS `sed` is BSD, not GNU
- **Symptom**: a rename `sed 's#~/Old\b#~/New#'` didn't match; paths got collapsed wrong.
- **Cause**: BSD `sed` (macOS default) lacks `\b` and other GNU regex extensions; `-i` requires an
  explicit backup suffix (`sed -i ''`).
- **Rule**: don't use GNU-only regex on macOS `sed`; verify substitutions with a follow-up `grep`,
  or use `perl -pe` for richer regex.

### 14. The headless smoke watchdog can kill the app prematurely under build load
- **Symptom**: smoke screenshot run exits 137 with no shot right after a release build.
- **Cause**: the kill-watchdog fires before the app finishes booting while the machine is busy
  compiling, not a real hang.
- **Rule**: give the smoke run a generous window (~30–40 s); retry once the build settles before
  concluding there's a hang. Build each feature group and confirm `swift build` is clean before moving on.

### 15. A stale incremental build can produce a binary that hangs at launch
- **Symptom**: after rapid edits + mixing `swift build` (debug) and an incremental `bundle.sh`
  (release), the app launched into a **100%-CPU SwiftUI scene-instantiation loop** (caught with
  `sample <pid>`); a clean rebuild ran fine with no code change.
- **Rule**: when the app hangs at launch after back-to-back/mixed incremental builds, **`rm -rf
  .build dist` and rebuild before bisecting code**. Profile a suspected hang with
  `sample <pid> 5 -file out.txt`: if it's all `AG::Graph::UpdateStack::update` / scene-list updates,
  it's a SwiftUI update cycle (or a bad build), not I/O.

### 16. SwiftUI materials flicker/blur behind a hosted `NSScrollView` (e.g. `TextEditor`)
- **Symptom**: glitchy shadowing/blurring around and under the prompt `TextEditor` in Settings.
- **Cause**: the Settings panel used a SwiftUI material (`.thickMaterial`); `TextEditor` is an
  AppKit `NSScrollView` hosted in SwiftUI, and its redraw/scroll re-samples the material behind it,
  producing flicker and shadow-like artifacts at the edges.
- **Rule**: don't put a SwiftUI **material** behind a hosted AppKit scroll view. Use a **solid**
  surface (`Color(nsColor: .windowBackgroundColor)` for panels, `.textBackgroundColor` for the
  editor fill). Solid is also the conventional macOS Settings look.

## External tools (yt-dlp)

### 17. `yt-dlp --sub-langs "en.*"` pulls every auto-translated track and triggers HTTP 429
- **Symptom**: caption fetch failed across a batch with "HTTP Error 429: Too Many Requests", and an
  odd subtitle track like `en-ar` in the message.
- **Cause**: the glob `en.*` matches not only `en`/`en-US`/`en-GB` but **every auto-translated
  track** (`en-ar`, `en-fr`, `en-de`, …). yt-dlp downloads one file per matched language, so it made
  ~30 subtitle requests per video; across a batch that tripped YouTube's rate limit. One track's 429
  fails the entire run.
- **Rule**: request **specific** subtitle codes (`<lang>,<lang>-orig,<lang>-US,<lang>-GB`), never
  `<lang>.*`. Add `--sleep-requests` + `--retries`/`--extractor-retries` to be gentle, and classify
  `429` / "too many requests" as a **transient/retryable** error so the job queue backs off (we use
  `YouTubeError.rateLimited`) instead of hard-failing the batch.

### 19. YouTube "Sign in to confirm you're not a bot" (anti-bot gate, not 429)
- **Symptom**: caption fetch fails with `Sign in to confirm you're not a bot. Use
  --cookies-from-browser or --cookies...`. Distinct from HTTP 429; retrying the same way doesn't help.
- **Cause**: YouTube's anti-bot gate, keyed on IP reputation (VPN / datacenter IPs, sometimes plain
  residential bad luck) and, very often, an out-of-date yt-dlp (stale signature/JS extraction).
- **Rule**: classify it distinctly (`YouTubeError.signInRequired`) with an actionable message and do
  NOT auto-retry (it needs user action). Mitigations, in order: (1) update yt-dlp; (2) drop the
  VPN/datacenter IP; (3) `--cookies-from-browser <browser>` to send a logged-in session; (4) the
  no-login `--extractor-args "youtube:player_client=..."` heuristic (a moving target). macOS cookie
  permissions: **Chrome** decrypts its cookie DB with the Keychain "Chrome Safe Storage" key (a
  one-time Keychain prompt); **Safari** cookies are TCC-protected, so the app needs **Full Disk
  Access** (and ad-hoc FDA grants reset on rebuild, learnings #3). `--cookies-from-browser` reads the
  whole browser cookie jar but only sends YouTube cookies to YouTube; say that truthfully in UI copy.

## Menu bar & custom panels

### 20. `MenuBarExtra` can't be opened or positioned programmatically
- **Symptom**: needed a global hotkey to reveal the menu-bar UI and to center the dropdown at the top
  of the screen — neither is possible with `MenuBarExtra`.
- **Cause**: SwiftUI's `MenuBarExtra` exposes no API to open its popover in code, and it always hangs
  (with an arrow) directly off the status item.
- **Rule**: when you need to *open from a hotkey*, *center/position*, or *animate* it, hand-roll the
  surface — an `NSStatusItem` whose button toggles a borderless `NSPanel` hosting your SwiftUI via
  `NSHostingView`. You lose the free dismissal, so wire it yourself (#21–22). If you *don't* need
  those, `NSPopover(.transient)` gives click-outside + Esc dismissal for free.

### 21. A borderless `NSPanel` can't become key → Esc/keys don't reach it
- **Symptom**: the custom panel showed, but Esc-to-close (a local key monitor) never fired.
- **Cause**: borderless `NSWindow`/`NSPanel` returns `canBecomeKey == false` by default, so it never
  becomes key or receives key events.
- **Rule**: subclass and override `var canBecomeKey: Bool { true }`, then `makeKeyAndOrderFront` +
  `NSApp.activate(ignoringOtherApps:)` so a local `keyDown` monitor sees Esc.

### 22. A *global* mouse monitor doesn't see your own app's clicks (use it for click-outside)
- **Symptom**: wanted "click anywhere outside to dismiss" without the status-item click instantly
  re-opening it (a toggle race).
- **Cause/insight**: `NSEvent.addGlobalMonitorForEvents` observes events destined for **other** apps
  only — your own status-item/panel clicks aren't delivered to it. (`addLocalMonitorForEvents` sees
  your app's events; return `nil` to swallow.)
- **Rule**: dismiss a custom panel with a **global** mouse-down monitor (catches clicks in any other
  app, incl. Finder/desktop) + a **local** key monitor for Esc + the status button for toggle. Because
  the global monitor ignores your own clicks, the icon toggle and click-outside don't fight. Install
  on show, remove on close.

## Animation: prefer explicit Core Animation

### 23. Window-frame animation is silently disabled by "Reduce Motion"
- **Symptom**: a slide built with `window.setFrame(_:display:animate: true)` *and* with
  `window.animator().setFrame(…)` just snapped — "the slide still doesn't work" over several attempts.
- **Cause**: AppKit window-frame animation honors the system **Reduce Motion** accessibility setting
  (it no-ops when on), and is additionally flaky for borderless/non-activating panels.
- **Rule**: don't animate the window frame for these effects. Keep the window fixed and animate the
  **content layer** with an explicit **`CABasicAnimation`** (e.g. `transform.translation.y`). Explicit
  Core Animation runs regardless of Reduce Motion; the window clips anything translated past its frame,
  so "slide down from behind the menu bar" falls out naturally.

### 24. A window shadow lingers at the frame while you animate the content layer
- **Symptom**: during a content-layer slide, a thin **~1px outline** appeared instantly at the panel's
  final position and stayed put while the content moved; also a faint border alongside the shadow.
- **Cause**: `NSWindow.hasShadow` is computed from the **window frame / model state**, not the
  animating presentation layer, so it sits at the final rectangle the whole time. A translucent
  borderless window's `hasShadow` also draws a subtle 1px chrome border.
- **Rule**: set `hasShadow = false` and draw your **own layer shadow** on a non-masked "shadowHost"
  view that contains the (masked, rounded) content. A layer shadow can be **faded** (animate
  `shadowOpacity`) and **slides with** the content. Make the **window slightly larger than the content**
  (a margin) so the soft layer shadow isn't clipped by the window frame (a layer shadow can't bleed
  outside the window the way a window shadow can).

## Vibrancy ("glass") & rounded corners

### 25. `NSVisualEffectView` ignores layer `cornerRadius` — round it with a `maskImage`
- **Symptom**: setting `blur.layer?.cornerRadius` + `masksToBounds` did nothing; corners stayed square.
- **Cause**: the vibrancy blur is rendered by the window server, not the view's layer, so it ignores
  layer corner masking.
- **Rule**: shape it with `maskImage` — a 9-slice `NSImage` (`capInsets`, `resizingMode = .stretch`).
  For **bottom-only** rounding, draw a rounded rect that extends *above* the image canvas so only the
  bottom corners curve within view: `NSBezierPath(roundedRect: NSRect(x:0,y:0,width:d,height:d+r),
  xRadius:r, yRadius:r)` into a `d×d` image. Put translucent SwiftUI content on top (e.g.
  `.background(Color.black.opacity(0.12))`) so the blur shows through; a SwiftUI `.clipShape` on the
  content is a cheap belt-and-suspenders. (Related to #16: don't fight materials behind hosted scroll
  views.)

## Swift 6 strict concurrency

### 26. Concurrency snags that bite when adding AppKit/Carbon
- **Shared non-`Sendable` global** (e.g. a `static let ISO8601DateFormatter`) is flagged as unsafe. If
  the use is read-only/thread-safe, mark it `nonisolated(unsafe) static let`.
- **`deinit` of a `@MainActor` class can't touch non-`Sendable` stored properties** (e.g. a Carbon
  `EventHotKeyRef`/`OpaquePointer`). Provide an explicit `func invalidate()` for the cleanup; don't
  reference those in `deinit`.
- **AppKit/Core Animation completion handlers** (`NSAnimationContext`, `CATransaction.setCompletionBlock`)
  run on main but aren't typed main-actor-isolated → wrap the body in `MainActor.assumeIsolated { … }`.
- **A C function-pointer callback** (Carbon `InstallEventHandler`) must be **non-capturing**; share
  state via `nonisolated(unsafe) static` storage keyed by id.
- **Blocking `Process`** (`run` + `waitUntilExit`) inside an `async` function stalls the caller's actor
  — run it on `DispatchQueue.global()` inside `withCheckedThrowingContinuation`. (Relevant to spawning
  `yt-dlp`/helpers without freezing the UI.)

## Global hotkeys

### 27. Carbon `RegisterEventHotKey` is a system hotkey that needs *no* Accessibility permission
- **Insight**: unlike `CGEvent` taps / consuming global monitors (which require Accessibility), Carbon
  `RegisterEventHotKey` registers a true global hotkey with no permission prompt.
- **Rule**: install one shared `InstallEventHandler` (non-capturing C callback, #26) and dispatch by
  `EventHotKeyID.id`. To **record** a shortcut, read the **virtual key code** (`event.keyCode`) +
  `event.modifierFlags` from an AppKit view's `keyDown(with:)` — the keyCode is what `RegisterEventHotKey`
  needs (the typed character isn't enough). Carbon masks: `cmdKey` 256, `shiftKey` 512, `optionKey`
  2048, `controlKey` 4096.

## Packaging, distribution & headless verification

### 28. `.dmg` for distribution (complements #12's `.icns`)
- **Rule**: stage a folder with `<App>.app` + a symlink `ln -s /Applications`, then `hdiutil create
  -volname "<Name>" -srcfolder <stage> -ov -format UDZO out.dmg` → a drag-to-Applications window.
  Unsigned/ad-hoc apps are **quarantined on download**, so the first launch needs **right-click → Open**
  (or `xattr -dr com.apple.quarantine /Applications/<App>.app`). (Re #3: ad-hoc has no stable identity.)

### 29. Build a menu-bar/agent app with SwiftPM (no Xcode project)
- **Rule**: a SwiftUI app builds as a SwiftPM `executableTarget` (`@main App` + a no-op `Settings { }`
  scene); set `NSApp.setActivationPolicy(.accessory)` and `LSUIElement = true` for a status-bar-only,
  no-Dock app. Own `NSStatusItem`/windows from an `AppDelegate` via `@NSApplicationDelegateAdaptor`;
  observe an `@Observable` from AppKit with `withObservationTracking { … } onChange:` (re-arm each
  fire). Resolve spawned-tool paths explicitly — **Finder-launched `.app`s don't inherit your shell
  `PATH`**, so `yt-dlp`/helpers won't be found by bare name.

### 30. `ImageRenderer` is great for headless SwiftUI snapshots — with sharp edges
- **Rule**: `ImageRenderer` rasterizes SwiftUI to PNG with no window server (good for CI/verification),
  but **`ScrollView` content renders blank** (no viewport — render a flat, non-scrolling variant), and
  **AppKit-backed controls don't rasterize** (`Toggle`/`NSSwitch`, segmented `Picker`, `NSVisualEffectView`
  show a yellow "no" placeholder — verify those in the real app; use a solid background as a vibrancy
  stand-in). A **byte-identical** render across a change is strong evidence the change had no effect
  (how the macOS `dynamicTypeSize` no-op, #10, got caught).

### 31. `screencapture -R` and `hdiutil` parsing gotchas
- **`screencapture -R x,y,w,h` uses PIXELS on Retina, not points** — multiply point coords by the
  backing scale (`capturedPixelWidth / screenPointWidth`, = 2 on Retina) or the region lands in the
  wrong place. (Capturing a live menu-bar panel reliably is hard regardless — prefer `ImageRenderer`.)
- **Parsing `hdiutil attach` output** breaks on volume names with spaces (`awk '{print $NF}'` grabs
  only the last word) — use `grep -o '/Volumes/.*'`.

### 32. A translucent overlay + blur shadow over the live app flickers when a section hosts an NSScrollView
- **Symptom**: with the Settings overlay open, the dim shroud and the panel's drop-shadow halo
  flickered, but only on sections that host an AppKit scroll view (Styles' `List`/`TextEditor`,
  Library, …); pure-SwiftUI sections were fine.
- **Cause**: the in-window Settings overlay stacked two translucent SwiftUI layers directly over the
  live app: a `Color.black.opacity(0.35)` shroud over the app's `.behindWindow` vibrancy +
  `.ultraThinMaterial` surfaces, and the panel's `.shadow(radius: 34)` (an offscreen Gaussian blur)
  composited over that same stack. A hosted `NSScrollView` repaints on AppKit's own clock (scroll,
  caret, relayout), marking its region dirty; CoreAnimation then re-composites that rect, re-running
  the offscreen shadow blur AND re-blending the translucent shroud over the still-re-sampling
  materials. Those passes aren't frame-synchronized, so for a frame or two the region shows a
  half-updated backdrop. This is #16 generalized (translucent compositing over hosted NSScrollViews).
- **Rule**: don't stack a translucent SwiftUI layer + a blur `.shadow` directly over the live,
  vibrancy-heavy app. Make the backdrop a real **`NSVisualEffectView`** glass pane
  (`blendingMode: .withinWindow`) so the blur is the window server's own hosted layer (it frosts the
  static app behind it rather than a SwiftUI re-blend), and **drop the panel's `.shadow`** (the
  offscreen blur was the other half of the flicker); an opaque panel over frosted glass reads as
  elevated on its own, and the app stays visible/frosted behind the modal. A hosted NSView doesn't
  forward SwiftUI tap gestures well, so put tap-to-close on a `Color.clear` layer above the glass.
  (Don't `.drawingGroup()` to flatten it instead: Metal rasterization breaks hosted AppKit views,
  #30. A solid opaque dim also kills the flicker but hides the app, which looks bland.)

## Meta-rule
When a fix doesn't work after **two** attempts, stop guessing: add a diagnostic that reports the
actual state/return values, or reproduce the primitive in isolation (a tiny script / standalone
binary) before trying a third variation.
