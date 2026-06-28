# Feature Specification: Summarize a YouTube playlist (YouTube mode)

**Feature Branch**: `007-playlist-summarize`

**Created**: 2026-06-29

**Status**: Draft

**Input**: User: "Get all the videos from a certain playlist, then summarize them all one by one
through a selected style." Converged design (via mockups): a thin left **mode rail**
(Transcripts / YouTube); YouTube mode hosts a video-or-playlist input with an inline picker.

## Background

Sumbee already turns single YouTube videos into summaries (`YouTubeService` + the batch queue), and
styles are already scoped by `StyleChannel` (`.file` drop zones vs `.youtube` buttons). What's
missing is (a) a way to enumerate a playlist and (b) a home for it that doesn't crowd the file view.
Enumeration is proven: `yt-dlp --flat-playlist --print "%(playlist_index)s|||%(id)s|||%(title)s|||%(url)s"`
lists a playlist with no extra dependency; unlisted playlists need no auth, private ones reuse the
cookie modes (005). The summarize-each-one part is just the existing queue.

## Clarifications (resolved in conversation)

- **Where it lives:** a thin left **mode rail** switching the main panel between **Transcripts**
  (file drop zones) and **YouTube**. This surfaces the existing `StyleChannel` split as top-level
  navigation, and gives the playlist picker an inline home (no modal).
- **Styles:** already channel-scoped, so YouTube mode shows `youtubeStyles`, Transcripts shows
  `fileStyles`. No model change.
- **Library:** stays **global** - the rail switches *input*, not what the library shows. (An optional
  origin filter is a future enhancement, not this feature.)
- **Access:** `yt-dlp --flat-playlist`; unlisted = no auth, private = the existing YouTube auth mode
  (cookies). The official Data API is not used (extra key/OAuth/quota for no gain).

## User Scenarios & Testing

### User Story 1 - Switch to a YouTube workspace (Priority: P1)
**Acceptance**:
1. A thin rail shows **Transcripts** and **YouTube**; selecting one switches the main panel.
2. Transcripts mode is the existing file drop-zone grid (unchanged). YouTube mode shows the URL
   input and the YouTube-channel styles. Default mode is Transcripts.
3. The library (right column) is unchanged by the mode and keeps showing all summaries.

### User Story 2 - Summarize a whole playlist (Priority: P1)
**Acceptance**:
1. In YouTube mode, pasting a **playlist URL** and choosing **Fetch** lists the videos
   (index + title) via `yt-dlp --flat-playlist`, honoring the YouTube auth mode for private lists.
2. The list is a checklist with **Select all / None**; videos already summarized for the chosen style
   are shown distinctly and **excluded by default** (dedup).
3. A **selected count** (and rough estimate) is visible; **Summarize** enqueues the selected videos
   as YouTube jobs on the chosen style, processed one at a time by the existing queue.
4. One failed/caption-less video does not abort the batch (existing queue behavior).

### User Story 3 - A single video still works (Priority: P2)
**Acceptance**:
1. In YouTube mode, pasting a **single video URL** behaves exactly as today: pick a YouTube style,
   summarize one. (Playlist UI appears only for playlist URLs.)

### Edge Cases
- Playlist with no captions on some videos → those jobs fail individually with the existing message.
- Private playlist without a cookie mode set → fetch fails with an actionable message (set cookies in
  Settings ▸ YouTube).
- Empty/invalid playlist URL → a clear hint; no fetch.
- A `watch?v=…&list=…` URL is treated as a **single video** in v1 (paste the `playlist?list=` URL to
  get the whole list); a future enhancement can offer "summarize the whole list instead".
- Very large playlists (100+) → all enumerate (flat-playlist is one request); summarizing many is the
  user's choice and shown as a count before they commit. Rate limits are handled by the existing
  yt-dlp throttling + retry/backoff.

## Requirements

### Functional Requirements
- **FR-068**: A thin left **mode rail** MUST switch the main panel between **Transcripts** and
  **YouTube** (default Transcripts). It is global navigation, present in both modes.
- **FR-069**: Transcripts mode MUST show the file-channel drop zones (unchanged). YouTube mode MUST
  host the YouTube URL input and the YouTube-channel styles (moved out of the always-on main panel).
- **FR-070**: A single video URL in YouTube mode MUST behave as today (pick a style → one summary).
- **FR-071**: A playlist URL in YouTube mode MUST be enumerable via `yt-dlp --flat-playlist`
  (honoring the YouTube auth mode for private lists), producing an inline checklist of videos
  (index + title) with Select all / None.
- **FR-072**: The picker MUST exclude videos already summarized for the chosen style by default
  (dedup via the summary's recorded source), show them distinctly, and display the selected count.
- **FR-073**: Summarize MUST expand the selected videos into the existing batch queue as YouTube jobs
  on the chosen style (sequential, individual failures isolated, existing retry/rate-limit handling).
- **FR-074**: The library MUST remain global (the rail switches input only).
- **FR-075**: No new third-party dependency; Transcripts mode and all existing behavior unchanged;
  build clean and tests green, including new enumeration-parse, playlist-URL-validation, and dedup
  tests.

### Out of scope (this feature)
- A persistent per-video status / resume panel (Direction C) - future.
- An origin filter in the library, and `watch?v=…&list=` "summarize whole list" disambiguation.
- Watch Later / the YouTube Data API.

## Success Criteria
- **SC-001**: From a pasted playlist URL, a user can fetch, trim (with already-done excluded), and
  summarize the selected videos through a chosen YouTube style, one at a time.
- **SC-002**: Transcripts mode and single-video YouTube behavior are unchanged.
- **SC-003**: `swift build` clean (0 warnings), `swift test` green with new unit tests; no new
  dependency; a release `.app` bundle builds.
