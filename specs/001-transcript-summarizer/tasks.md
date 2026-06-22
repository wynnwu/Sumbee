# Tasks: Transcript & Video Sumbee

**Input**: Design documents from `specs/001-transcript-summarizer/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md
**Tests**: Included (light) per the user request - deterministic core only.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: parallelizable (different files, no dependency)
- **[Story]**: US1 (file summarize), US2 (YouTube), US3 (styles CRUD), US4 (library browser)
- Paths are under `Sumbee App/` (repo feature root).

---

## Phase 1: Setup (Shared Infrastructure)

- [ ] T001 Create `Package.swift` (tools 6.0, macOS 15, targets `SumbeeKit` lib + `Sumbee` exe + `SumbeeKitTests`, language mode v5).
- [ ] T002 [P] Add `README.md`, `LICENSE` (MIT), `.gitignore` (.build, dist, .DS_Store, .specify caches as appropriate).
- [ ] T003 [P] Add `scripts/bundle.sh` (build release → assemble `dist/Sumbee.app` + `Info.plist` → ad-hoc codesign) and `scripts/make-icon.sh` (generate `AppIcon.icns`).
- [ ] T004 Create source tree skeleton dirs under `Sources/SumbeeKit/{App,Models,Services,Services/Extractors,State,Views/{MainPanel,AssetBrowser,BottomBar,Settings,Design}}` and `Sources/Sumbee/`.

---

## Phase 2: Foundational (Blocking Prerequisites)

**⚠️ Must complete before user-story work.**

- [ ] T005 [P] `Models/SummaryStyle.swift` - `SummaryStyle`, `Channel`, `ModelOverride`.
- [ ] T006 [P] `Models/Asset.swift` - `Asset`, `SourceRef`, `OutputFormat`.
- [ ] T007 [P] `Models/AppSettings.swift` - versioned `Codable` settings + load/save (Application Support).
- [ ] T008 [P] `Models/ModelCatalog.swift` - presets + `ModelCapabilities` (temperature/effort/thinking/ceiling) + lookup with conservative default.
- [ ] T009 [P] `Services/FrontmatterCodec.swift` - read/write YAML-ish frontmatter + body.
- [ ] T010 [P] `Services/Sanitizer.swift` - filename sanitize + collision suffixing.
- [ ] T011 [P] `Services/KeychainStore.swift` - Security-framework generic-password save/load/remove/hasKey.
- [ ] T012 `Views/Design/Theme.swift` + `GlassBackground.swift` + `Components.swift` - orange accent, materials, `NSVisualEffectView` representable, glass card / pill button / toast.
- [ ] T013 `State/AppState.swift` - `@MainActor` root store skeleton (settings, key-gate, library, jobs) wired to KeychainStore + AppSettings.
- [ ] T014 `App/SumbeeApp.swift` + `App/ContentView.swift` + `Sources/Sumbee/main.swift` - scene, window config (size/min/material), 3-region shell + bottom bar, `SumbeeApp.main()`.

**Checkpoint**: app builds and launches to an empty glass shell.

---

## Phase 3: User Story 1 - Summarize a dropped transcript (Priority: P1) 🎯 MVP

**Goal**: Drop a transcript onto a style → saved summary + archived source.
**Independent Test**: quickstart steps 1–3.

### Tests for US1 (write first)

- [ ] T015 [P] [US1] `Tests/SumbeeKitTests/FrontmatterCodecTests.swift` (round-trip).
- [ ] T016 [P] [US1] `Tests/SumbeeKitTests/SanitizerTests.swift` (sanitize + collisions).
- [ ] T017 [P] [US1] `Tests/SumbeeKitTests/ModelCatalogTests.swift` (capability gating).
- [ ] T018 [P] [US1] `Tests/SumbeeKitTests/PromptBuilderTests.swift` (md vs html convention; title instruction present).
- [ ] T019 [P] [US1] `Tests/SumbeeKitTests/DocxExtractorTests.swift` (tiny fixture → text).

### Implementation for US1

- [ ] T020 [P] [US1] `Services/Extractors/PlainTextExtractor.swift` (txt/md).
- [ ] T021 [P] [US1] `Services/Extractors/PDFExtractor.swift` (PDFKit; empty → no-text error).
- [ ] T022 [P] [US1] `Services/Extractors/RTFExtractor.swift` (`NSAttributedString`).
- [ ] T023 [P] [US1] `Services/Extractors/DocxExtractor.swift` (`unzip -p` + `XMLParser`).
- [ ] T024 [US1] `Services/TextExtractor.swift` (dispatch by UTType/extension; supported set; empty → error).
- [ ] T025 [US1] `Services/PromptBuilder.swift` (style prompt + format-aware §7.4 convention + optional HTML styling prompt; faithful-mode preamble guard).
- [ ] T026 [US1] `Services/AnthropicClient.swift` (URLSession SSE stream; capability-gated body; error mapping; `validateKey`).
- [ ] T027 [US1] `Services/StyleStore.swift` (parse/serialize style-definition.md; `loadStyles`; `seedDefaults` with the 5 source styles).
- [ ] T028 [US1] `Services/LibraryStore.swift` (scan styles + assets + `source`; ensure folders).
- [ ] T029 [US1] `Services/SummarizationEngine.swift` (extract → archive source → build prompt → stream → parse title → sanitize → write asset w/ frontmatter).
- [ ] T030 [US1] `Services/JobQueue.swift` (sequential queue; per-job phase/progress; cancel; one failure ≠ batch abort).
- [ ] T031 [US1] `Views/MainPanel/{FileStylesSection,DropZoneView}.swift` (dynamic drop zones; drag highlight; reject unsupported; click→picker; per-zone job state).
- [ ] T032 [US1] `Views/BottomBar/BottomBarView.swift` (gear → Settings; job status; error toasts).
- [ ] T033 [US1] `Views/Settings/{SettingsView,APIKeySection,ModelSection,LibrarySection}.swift` (key gate + Save&Validate; model picker + capability-aware controls; library folder picker).
- [ ] T034 [US1] Wire `AppState` ↔ JobQueue/Engine/Library/Style/Keychain; enforce key gate (open Settings if no key; re-gate on 401).

**Checkpoint**: drop a file → saved summary; no key → gated to Settings.

---

## Phase 4: User Story 3 - Create and edit styles (Priority: P2)

**Goal**: Full style CRUD reflected live in the main window.
**Independent Test**: spec US3 independent test.

- [ ] T035 [US3] Extend `StyleStore` with `create/update/rename(move folder)/delete(keep assets)`.
- [ ] T036 [US3] `Views/Settings/StylesCRUDSection.swift` (list, channel, enable toggle, reorder, editor, reset-to-defaults, delete warning).
- [ ] T037 [P] [US3] `Tests/SumbeeKitTests/StyleStoreTests.swift` (definition parse/serialize round-trip; rename keeps id).
- [ ] T038 [US3] Live update: AppState reloads styles after CRUD so main-window zones/buttons refresh.

**Checkpoint**: create/rename/delete styles; main window updates.

---

## Phase 5: User Story 2 - Summarize a YouTube video (Priority: P2)

**Goal**: URL + style button → saved summary from captions.
**Independent Test**: spec US2 independent test (needs yt-dlp + network).

- [ ] T039 [P] [US2] `Services/VTTParser.swift` (strip cues/timestamps; dedupe rolling lines; optional coarse timestamps).
- [ ] T040 [P] [US2] `Tests/SumbeeKitTests/VTTParserTests.swift` (rolling-caption dedupe; timestamp retention).
- [ ] T041 [US2] `Services/YouTubeService.swift` (locate yt-dlp; URL validation; fetch via `Process`; metadata; update/download action).
- [ ] T042 [US2] Engine `summarizeYouTube` path (fetch → clean → archive transcript → summarize → save with URL metadata).
- [ ] T043 [US2] `Views/MainPanel/YouTubeSection.swift` (URL field; per-style buttons; disabled+hint on invalid; missing-tool state).
- [ ] T044 [US2] `Views/Settings/YouTubeSettingsSection.swift` (caption language; yt-dlp status + Update action; custom path).

**Checkpoint**: paste URL → summary saved (when yt-dlp present).

---

## Phase 6: User Story 4 - Browse & manage the library (Priority: P3)

**Goal**: Grouped, live, actionable library browser with preview.
**Independent Test**: spec US4 independent test.

- [ ] T045 [P] [US4] `Services/DirectoryWatcher.swift` (FSEvents recursive watch → onChange).
- [ ] T046 [US4] `Views/AssetBrowser/{AssetBrowserView,AssetRowView}.swift` (groups by style + source; newest-first; selection).
- [ ] T047 [US4] `Views/AssetBrowser/MarkdownPreview.swift` (read-only preview).
- [ ] T048 [US4] Asset actions: reveal in Finder, open externally, copy, delete.
- [ ] T049 [US4] Wire DirectoryWatcher → AppState → live refresh (and refresh after each saved asset).

**Checkpoint**: browse/preview/act; Finder changes reflected.

---

## Phase 7: Polish & Cross-Cutting

- [ ] T050 [P] `Services/HTMLMetaCodec.swift` + Engine HTML path + `Views/Settings/OutputFormatSection.swift` (Markdown/HTML toggle; shared HTML-styling prompt).
- [ ] T051 [P] Privacy note in Settings (FR-019); empty/oversized-input handling notices (FR-007).
- [ ] T052 [P] Accessibility/keyboard pass (focus order, labels, Dark/Light contrast check).
- [ ] T053 Generate app icon (`scripts/make-icon.sh`) and reference it in the bundle.
- [ ] T054 Build `.app` via `scripts/bundle.sh`; launch; capture screenshot(s) verifying glass UI + key gate (quickstart verify).
- [ ] T055 Run `swift test`; ensure green. Update `README.md` with build/run/verify + architecture overview.
- [ ] T056 Multi-agent adversarial review (correctness-vs-spec, key-handling security, concurrency, UI/design, requirement-coverage); fix confirmed findings.

---

## Phase 8: Revision 2 - Reliability, Drop UX, Live Models

- [ ] T057 [US1] Retry queue (FR-021): split `SummarizationEngine` into `prepare`/`finish`;
  add `attempt`/prepared-cache fields + `.waitingRetry(Date)` phase to `Job`; rework
  `AppState+Jobs` with retryable classification, exponential backoff (cap 5 min), a 1s
  promotion ticker, and `runQueueNow()`; add `AnthropicError.unavailable` (403/404).
- [ ] T058 [US1] Bottom bar "Run queue" button + waiting/countdown status.
- [ ] T059 [US1] Square dotted drop tiles (FR-022): `LazyVGrid` in `FileStylesSection`;
  `DropZoneView` square tile + `FileDropDelegate` (valid-type hover → solid orange border,
  outer glow, lift).
- [ ] T060 [US1] Live models (FR-023): `AnthropicClient.listModels`; `AppState.availableModels`
  + fetch on Settings open / key save; `GenerationSection` picker uses live list with preset
  fallback; tests for model parse + retry classification.
- [ ] T061 Rebuild `.app`, `swift test`, launch-verify; focused review of the retry logic.

## Phase 9: Revision 3 - UI refinement

- [ ] T062 Bottom-bar model menu (FR-024): make the model chip a `Menu` over `availableModels`.
- [ ] T063 Library tabs + one-line rows (FR-025): segmented Summaries/Source tabs in
  `AssetBrowserView`; `AssetRowView` → single line (title left, date right); parse the
  datetime-prefixed source names for display.
- [ ] T064 Datetime-prefixed source filenames (FR-026): `SummarizationEngine.archiveFile` /
  `archiveTranscript`.
- [ ] T065 Visual language (FR-027): `Theme` square corners + larger type; `Components`
  square buttons/chips; bigger fonts/icons across views; `DropZoneView` huge left-aligned
  faded name, no helper text.
- [ ] T066 Lively bottom-bar animation while summarizing (FR-028).
- [ ] T067 Rebuild `.app`, `swift test`, launch-verify.

## Dependencies & Execution Order

- Setup (P1) → Foundational (P2) → US1 (P3) is the critical path to MVP.
- US3 (P4), US2 (P5), US4 (P6) each depend only on Foundational + US1's stores/engine.
- Polish (P7) depends on the user stories it touches; T054–T056 are last.

## Parallel Opportunities

- All of Phase 2 models/services marked [P] (T005–T011) are independent files.
- US1 tests (T015–T019) and extractors (T020–T023) are independent [P].
- Cross-story leaf services (VTTParser T039, DirectoryWatcher T045, HTMLMetaCodec T050)
  are independent of each other.

## Implementation Strategy

MVP = Phases 1–3 (drop a file → saved summary, gated by key). Then layer US3 → US2 →
US4 → Polish, validating at each checkpoint, finishing with a verified `.app` build,
green tests, and an adversarial review pass.
