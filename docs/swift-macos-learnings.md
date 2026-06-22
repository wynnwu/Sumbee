# Swift / macOS learnings (hard-won)

Real bugs we hit building Sumbee and the rules that prevent them. Read before touching persistence,
permissions, the library list, fonts, icons, or shell scripts. Each entry: **Symptom → Cause → Rule.**

## Persistence

### 1. Adding a field to a `Codable` settings struct silently wiped ALL settings
- **Symptom**: after adding a property, users' saved config reset to defaults.
- **Cause**: synthesized `Codable` decoding **fails entirely** if a key is missing, and our loader
  fell back to `AppSettings()` on any decode error → total reset.
- **Rule**: settings use a **field-tolerant** `init(from:)` — every key is
  `decodeIfPresent(...) ?? default`. Adding a field must never fail to decode an older file.
  (See `AppSettings.swift` / research D15.) Add new fields to: properties, memberwise `init`,
  `CodingKeys`, **and** `init(from:)`.

## Permissions, TCC & signing

### 2. `~/Documents` (and Desktop/Downloads) are TCC-protected — "Reveal in Finder" silently opened Home
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
  **interactive** "allow access" dialog — which blocks, and can't be answered headlessly.
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

## Layout & typography

### 10. `.dynamicTypeSize` barely scales macOS's built-in text styles
- **Symptom**: "make the fonts bigger" via `.dynamicTypeSize(.xLarge)` did almost nothing.
- **Cause**: on macOS, Dynamic Type has little effect on the standard text styles.
- **Rule**: use **explicit point sizes** via a small shared font-token set (`Font.uiTitle/uiBody/…`)
  rather than relying on Dynamic Type. Fixed `.system(size:)` fonts don't scale with Dynamic Type
  either — that's a feature here.

### 11. `LazyVGrid(.adaptive)` inside `HSplitView` caused layout-cycle hangs
- **Rule**: avoid `.adaptive` grid columns inside `HSplitView`; use fixed/flexible columns.
  (Research D10.)

## Icons, build & tooling

### 12. Build `.icns` with `iconutil`, not by hand
- **Symptom**: the app icon rendered as colored garbage in Finder.
- **Cause**: the `.icns` was a single malformed `icp4` entry (a 1024px image under a 16×16 tag).
- **Rule**: produce icons with `iconutil -c icns Name.iconset` from a complete `.iconset`
  (16…1024, @1x/@2x). Validate by extracting back: `iconutil -c iconset Name.icns`. For the two
  smallest sizes, ship a simplified mark (we use bee-only) — fine detail is illegible at 16/32 px.

### 13. macOS `sed` is BSD, not GNU
- **Symptom**: a rename `sed 's#~/Old\b#~/New#'` didn't match; paths got collapsed wrong.
- **Cause**: BSD `sed` (macOS default) lacks `\b` and other GNU regex extensions; `-i` requires an
  explicit backup suffix (`sed -i ''`).
- **Rule**: don't use GNU-only regex on macOS `sed`; verify substitutions with a follow-up `grep`,
  or use `perl -pe` for richer regex.

### 14. The headless smoke watchdog can kill the app prematurely under build load
- **Symptom**: smoke screenshot run exits 137 with no shot right after a release build.
- **Cause**: the kill-watchdog fires before the app finishes booting while the machine is busy
  compiling — not a real hang.
- **Rule**: give the smoke run a generous window (~30–40 s); retry once the build settles before
  concluding there's a hang. Build each feature group and confirm `swift build` is clean before moving on.

### 15. A stale incremental build can produce a binary that hangs at launch
- **Symptom**: after rapid edits + mixing `swift build` (debug) and an incremental `bundle.sh`
  (release), the app launched into a **100%-CPU SwiftUI scene-instantiation loop** (caught with
  `sample <pid>`); a clean rebuild ran fine with no code change.
- **Rule**: when the app hangs at launch after back-to-back/mixed incremental builds, **`rm -rf
  .build dist` and rebuild before bisecting code**. Profile a suspected hang with
  `sample <pid> 5 -file out.txt` — if it's all `AG::Graph::UpdateStack::update` / scene-list updates,
  it's a SwiftUI update cycle (or a bad build), not I/O.

## Meta-rule
When a fix doesn't work after **two** attempts, stop guessing: add a diagnostic that reports the
actual state/return values, or reproduce the primitive in isolation (a tiny script / standalone
binary) before trying a third variation.
