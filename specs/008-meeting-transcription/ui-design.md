# Meetings UI direction

Applied the installed `frontend-design` skill after the real offline feasibility run recorded
in validation-results.md. Accuracy validation remains an explicit release gate.

## Design plan and review

This is a native working transcript for someone returning to an hour-long conversation.
Keep Sumbee's existing system font tokens, orange action accent, rail, and library layout.
The defining element is the conversation itself: a quiet timestamp gutter, speaker names, and
editable paragraphs. A waveform, decorative dashboard metrics, and per-turn cards would compete
with reading; omit them. Use one review sheet large enough to read and correct a conversation.

Color roles use macOS dynamic colors: window background (light reference #ECECEC), text surface
(#FFFFFF), primary text (#1C1C1E), secondary text (#636366), separator (#D1D1D6), plus existing
Theme.accent orange. Hex values describe the light palette; system equivalents adapt to dark
mode and accessibility. Do not hard-code light colors. Use solid surfaces behind TextEditor
and native scroll views, following the repository's macOS rendering learnings.

Type: existing rounded SF `.uiTitle` for headings, `.uiHeadline`/`.uiBody` for speaker controls
and transcript, `.uiCaption` for context; timestamps use monospaced digits only. Left align
text, constrain transcript reading width, use 20-point outer padding and 12–16-point grouping.
Native focus rings and standard controls carry keyboard affordance. Animation is limited to
system transitions and indeterminate progress during actual work.

```
Meetings                         Participants…
Audio stays on this Mac. Summary text is sent only when requested.
[ Import recordings… ]
Model setup / copy progress / current stage, when applicable
Meeting title                    duration / status
Meeting title                    duration / status

Review: Meeting title                          Done
[ Play / Pause ]  position ------- duration    Reveal audio
Speakers [Speaker 1…] [Speaker 2…]   Attendees…
00:01:12  Speaker 1                       [Edit] [Assign turn…]
          The conversation text continues here…
00:01:34  Suggested: Alex                [Confirm] [Choose…]
          More text…
[ Export transcript ]    [ Style picker ] [Summarize…]
```

## States and actions

- Empty: invite import of WAV, MP3, or M4A. No API-key gate on local work.
- Models missing: state the ~486 MB one-time download, local storage, and explicit Download
  action. Show actual downloaded bytes/files and a separate verification stage; allow cancel.
  A failed install retains the previous working installation and offers retry.
- Copying: transient filename and indeterminate progress with cancel. A failed or cancelled
  copy leaves no saved row and tells the user to import again.
- Processing: use actual stages: loading models, transcribing, identifying speakers, preparing
  transcript. No invented percentages. Cancel acknowledges immediately; if an SDK call is
  finishing, explain that the next queued recording will wait for it.
- Failed/interrupted: keep saved audio, offer Retry. Ready content has no reprocess action.
- No speech: explicit message; local playback remains available, summary action unavailable.
- Untimed text: label Untimed, offer nearby playback without claiming an exact citation.
- Review: edit a paragraph explicitly with Save/Cancel; reassign a turn to an existing or new
  speaker; merge speaker groups from the speaker controls. Preserve all text and reading order.
- Speaker naming: searchable catalog with duplicate-name context (creation date/short ID and
  remembered sample context). Suggestions read “Suggested: Name” until explicitly confirmed.
  Reject returns to a generic label. No scores or threshold controls.
- Remember voice: separate explicit action after confirmation. Show plain eligibility reason
  when unavailable, with guidance to use another recording. Naming alone never remembers a voice.
- Participants: search, add, rename, merge, delete, remove voice sample. Delete confirmation
  explains that historical transcript wording stays readable while future recognition stops.
- Export: latest confirmed catalog names, saved fallback for deleted people, generic labels
  for unconfirmed speakers. Each export is a new immutable file.
- Summary: choose an existing file style, explain text transmission, require explicit action.
  Meeting Notes style is an opt-in creation action that preserves existing edited styles.

## Keyboard and verification

Audio-only deletion uses a visible **Delete audio…** button in each meeting row and the
review header, followed by a destructive confirmation naming the meeting and explaining
the scope. The transcript, names, remembered voices, models, exports, summaries and original
input are kept. The review stays open after deletion; playback is disabled with an
audio-unavailable message. Deletion is disabled while processing is queued, active or still
stopping; library changes dismiss confirmation. Full meeting deletion is not included.

Tab order follows visible reading order. Every timestamp has a “Play from…” accessibility
label; icon-only controls have names. Escape dismisses sheets or cancels an edit without
saving. Return invokes a focused primary action, not a destructive catalog operation.
Use native menus, pickers, alerts, selection, and text editing rather than gesture-only controls.
Verify narrow window, long names, untimed turns, failed setup, light/dark, VoiceOver labels,
and a real local playback/correction flow after integration. Record observed results separately.
