# Implementation Plan: Transcript & Video Sumbee

**Branch**: `001-transcript-summarizer` | **Date**: 2026-06-20 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/001-transcript-summarizer/spec.md`

## Summary

Build a native macOS app that turns transcripts (`.txt/.md/.pdf/.docx/.rtf`) and
YouTube videos (via captions) into saved Markdown/HTML summaries, where each summary
"style" is a user-editable prompt that names a folder in a user-owned library. The
app streams summaries from the Anthropic Messages API (key held in Keychain),
archives every source, and presents a glass/orange, light-and-dark, futuristic but
restrained single-window UI. Technical approach: a SwiftPM package with a testable
`SumbeeKit` library and a thin executable shell bundled into a `.app`, **zero
third-party/build-time-network dependencies** — every parser and integration uses a
system framework or system binary (PDFKit, `NSAttributedString`, `XMLParser` +
`/usr/bin/unzip`, `URLSession` SSE, Security/Keychain, `Process` for yt-dlp).

## Technical Context

**Language/Version**: Swift 6.2 toolchain (SwiftPM `swift-tools-version: 6.0`,
language mode v5 for a frictionless first build; strict-concurrency migration is a
documented later step).

**Primary Dependencies**: None third-party. System frameworks only — SwiftUI, AppKit,
Foundation, PDFKit, Security, UniformTypeIdentifiers, CoreServices (FSEvents). System
binary: `/usr/bin/unzip` (DOCX). External user tool (runtime, optional): `yt-dlp`.

**Storage**: Plain files in a user-chosen library root (summaries + archived sources +
on-disk style definitions). App settings in JSON under Application Support. API key in
the macOS Keychain. No database.

**Testing**: XCTest via `swift test`, targeting the deterministic core of
`SumbeeKit`.

**Target Platform**: macOS 15 (Sequoia)+, universal (arm64 + x86_64).

**Project Type**: Single native desktop app (SwiftPM package → `.app` bundle).

**Performance Goals**: UI stays at 60 fps and fully interactive during jobs; all I/O,
parsing, network, and process spawning happen off the main actor; summary output is
streamed token-by-token to the UI.

**Constraints**: No build-time network; no third-party packages; API key never leaves
the Keychain except in-memory at request time; offline browsing/opening of existing
summaries must work; one window.

**Scale/Scope**: Single-user personal tool; ~25–35 source files; ~5 seeded styles,
unbounded user styles; libraries from tens to thousands of summary files.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|---|---|---|
| I. Native-First, Zero-Friction Build | PASS | SwiftPM + `.app` bundler; zero third-party deps; builds offline with the Apple toolchain. |
| II. Testable Core, Thin Shell | PASS | `SumbeeKit` library holds all logic; `Sumbee` executable is a 1-line shell; tests import the library. |
| III. Local-First & Privacy | PASS | Only Anthropic + YouTube calls leave the machine; offline browsing supported; privacy note in Settings. |
| IV. Secure Secret Handling | PASS | Keychain-only key, read at request time, never logged/persisted; auto re-gate on 401; remove-key action. |
| V. User-Owned, Plain-File Data | PASS | Library folder is the source of truth for summaries and styles; usable with the app closed. |
| VI. Beautiful, Accessible, Native UI | PASS | NSVisualEffectView vibrancy, `.ultraThinMaterial`, orange accent, auto light/dark, keyboard-operable, off-main-thread work. |
| VII. Pragmatic, Growable Testing | PASS | Unit tests for the deterministic core + verified build/launch; full suite deferred by design. |

No violations. Complexity Tracking is empty.

## Project Structure

### Documentation (this feature)

```text
specs/001-transcript-summarizer/
├── plan.md              # This file
├── spec.md              # Feature spec (WHAT/WHY)
├── research.md          # Phase 0: decisions & rationale
├── data-model.md        # Phase 1: entities & on-disk formats
├── quickstart.md        # Phase 1: build/run/verify
├── contracts/
│   ├── anthropic-messages.md   # Outbound API request/stream contract
│   ├── ipc-surface.md          # AppState ⇄ SumbeeKit service contract
│   └── file-layout.md          # Library/asset/source/style on-disk contract
├── checklists/
│   └── requirements.md
└── tasks.md             # Phase 2 output (/speckit-tasks)
```

### Source Code (repository root = `Sumbee App/`)

```text
Package.swift                 # SwiftPM manifest (macOS 15, two targets + tests)
README.md                     # Project overview, build, contribute
LICENSE                       # MIT
.gitignore
scripts/
  bundle.sh                   # swift build -c release → assemble .app → ad-hoc sign
  make-icon.sh                # generate AppIcon.icns (orange glass mark)
Sources/
  Sumbee/                 # thin executable shell
    main.swift                # SumbeeApp.main()
  SumbeeKit/              # all logic + UI (library target)
    App/                      # SumbeeApp scene, ContentView, root wiring
    Models/                   # SummaryStyle, Asset, SourceRef, AppSettings, ModelCatalog
    Services/
      AnthropicClient.swift   # URLSession SSE streaming + error mapping
      KeychainStore.swift     # Security-framework key storage
      LibraryStore.swift      # scan styles+assets, FSEvents watch
      StyleStore.swift        # CRUD on <Style>/style-definition/style-definition.md
      TextExtractor.swift     # dispatch by type
      Extractors/             # PlainText, PDF (PDFKit), RTF (NSAttributedString), Docx (unzip+XMLParser)
      YouTubeService.swift    # yt-dlp discovery/invocation
      VTTParser.swift         # captions → clean transcript
      PromptBuilder.swift     # §7.4 output convention (md/html), system+user assembly
      FrontmatterCodec.swift  # YAML-ish frontmatter read/write
      HTMLMetaCodec.swift     # <meta>/comment metadata for HTML output
      Sanitizer.swift         # filename sanitize + collision suffixing
      SummarizationEngine.swift # extract→archive→prompt→stream→title→save
      JobQueue.swift          # sequential queue, progress, cancel
      DirectoryWatcher.swift  # FSEvents wrapper
    State/
      AppState.swift          # @MainActor root store: settings, gate, jobs, library
    Views/
      MainPanel/  AssetBrowser/  BottomBar/  Settings/  Design/
Tests/
  SumbeeKitTests/         # FrontmatterCodec, Sanitizer, VTTParser, StyleStore,
                              # PromptBuilder, ModelCatalog, DocxExtractor (fixture)
```

**Structure Decision**: Single SwiftPM package at the feature root. A `SumbeeKit`
library target owns 100% of logic and views; a tiny `Sumbee` executable target
provides `@main` via `SumbeeApp.main()` so the test target can import the library.
A `scripts/bundle.sh` wraps the built binary into a signed `.app` (no `.xcodeproj`,
no XcodeGen, no network). This directly serves Constitution principles I and II.

## Complexity Tracking

> No constitution violations — section intentionally empty.
