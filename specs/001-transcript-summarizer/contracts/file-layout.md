# Contract: On-Disk File Layout

The library is the source of truth. These formats are stable contracts; tests assert
the deterministic ones (filenames, frontmatter, style-definition parsing).

## Library tree

```text
<root>/
├── Meetings - General/
│   ├── style-definition/style-definition.md     # this style's prompt + metadata
│   └── 2026-06-20 1432 - Q2 Roadmap Sync.md
├── Meetings - Product Review/style-definition/style-definition.md
├── Interviews - Short/style-definition/style-definition.md
├── Interviews - Long/style-definition/style-definition.md
├── YouTube/style-definition/style-definition.md
└── source/
    ├── q2-sync__2026-06-20_143205.docx
    └── dQw4w9WgXcQ__2026-06-20_145511.txt
```

A folder is a **style** iff it contains `style-definition/style-definition.md`.
`source/` has none, so it is never treated as a style; `style-definition/` is hidden
from asset listings.

## style-definition.md

```markdown
---
id: 6f1c0b2a-...        # stable UUID, survives folder renames
channel: file           # file | youtube
order: 1
enabled: true
# optional: model, temperature, effort, format
---
<prompt body here>
```

Display name = folder name. Renaming the folder (in app or Finder) keeps the prompt
attached; `id` tracks the style across renames.

## Asset filename

```text
YYYY-MM-DD HHmm - <Sanitized Title>.md        # .html when HTML output selected
```

- Date-time = job completion (local), zero-padded, filesystem-safe (no `:`).
- Title = model `#`/`<h1>` heading, **sanitized**: replace `/ \ : * ? " < > |`,
  collapse whitespace, trim to ~80 chars; fall back to source name if absent.
- **Collisions**: append ` (2)`, ` (3)`, … before the extension; never overwrite.

### Markdown metadata (YAML frontmatter)

```yaml
---
title: Q2 Roadmap Sync
style: Meetings - General
created: 2026-06-20T14:32:05-07:00
source: source/q2-sync__2026-06-20_143205.docx     # or a YouTube URL
model: claude-opus-4-8
---
```

### HTML metadata

Same fields as `<meta name="title|style|created|source|model" content="…">` inside
`<head>`, plus an optional leading `<!-- … -->` comment (YAML would render as text).

## Source archive

```text
YYYY-MM-DD_HHmmss__<original-basename>.<ext>     # datetime-prefixed (sorts chronologically)
```

Originals are **copied** (never moved) into `source/`. YouTube transcripts are written
as `<datetime>__<video-id>.txt`. The datetime is a **prefix** (FR-026) so archives sort
chronologically in Finder. Guarantees: delete the original, lose nothing.

## App config (not in the library)

`~/Library/Application Support/Sumbee/config.json` holds settings only (see data-model).
API key → Keychain. Both excluded from the library tree.
