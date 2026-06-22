# Quickstart: build, run, verify

Prerequisites: macOS 15+, Xcode 26+ (Swift 6.2 toolchain). No network needed to build.

## Build & run (development)

```bash
cd Sumbee
swift build            # debug build of the SwiftPM package
swift run Sumbee   # launches the app (debug)
```

## Test

```bash
swift test             # runs SumbeeKitTests (deterministic core)
```

## Produce the .app bundle

```bash
./scripts/bundle.sh    # swift build -c release → dist/Sumbee.app → ad-hoc sign
open dist/Sumbee.app
```

First launch (no key stored) opens to **Settings** with summarization disabled. Paste
an Anthropic API key, Save & Validate, then drop a transcript onto a style.

Gatekeeper note (local/unsigned v1): if macOS blocks first launch, right-click the
`.app` → Open, or `xattr -dr com.apple.quarantine dist/Sumbee.app`.

## Verify (acceptance smoke)

1. Launch with no key → app opens to Settings, drop zones disabled (US1 AS4).
2. Save a key → drop zones enable.
3. Drop a `.txt`/`.md`/`.pdf`/`.docx`/`.rtf` onto a file style → a `YYYY-MM-DD HHmm -
   <Title>.md` appears in that style's folder; original archived under `source/` (US1).
4. Toggle system Dark/Light → UI adapts; orange accent + glass remain legible (SC-009).
5. Browse: the right pane lists summaries grouped by style, newest first; reveal/open/
   copy/delete work; add a file in Finder → list updates (US4).
6. Optional (needs yt-dlp + network): paste a watch URL → press a YouTube style →
   summary saved, transcript archived, URL in metadata (US2).

## yt-dlp (optional, for YouTube)

If `yt-dlp` is on `PATH` or at `/opt/homebrew/bin` / `/usr/local/bin`, YouTube works.
Otherwise Settings → "Download/Update yt-dlp", or set a custom path. Absence only
disables the YouTube section; everything else works.
