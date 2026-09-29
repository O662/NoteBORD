# `.board` file format (v1)

A `.board` file is a **zip package**. The same layout is the on-disk storage for each notebook, so export is simply "zip the folder".

```
My notebook.board
├── notebook.json        # metadata, page order, settings
├── pages/
│   ├── <pageId>.json    # items on that page
│   └── ...
├── assets/
│   ├── <sha256>.png     # images, PDFs, audio, video (content-addressed)
│   └── ...
└── index/
    └── recognition.json # optional cache: handwriting text per stroke group
```

Locked notebooks and pages store `pages/<pageId>.json.enc` (AES-256-GCM) in place of the plain file, along with `lock.json` (salt, Argon2id parameters, hint).

## notebook.json
```json
{
  "format": "endless.board",
  "version": 1,
  "id": "nb_01J...",
  "title": "Physics — Lecture notes",
  "folderPath": ["School", "Physics"],
  "cover": { "color": "#2B5A8C" },
  "createdAt": "2026-09-01T14:00:00Z",
  "updatedAt": "2026-09-25T10:12:03Z",
  "pages": ["pg_01", "pg_02", "pg_03"],
  "defaults": { "paper": "dots", "theme": "paper" },
  "locked": false
}
```

## pages/<pageId>.json
```json
{
  "id": "pg_03",
  "title": "Lecture 3 — Momentum",
  "paper": "dots",
  "template": null,
  "locked": false,
  "items": [ /* Item[] in z-order */ ]
}
```

## Items
Every item has these fields:
```json
{ "id": "it_…", "type": "…", "x": 0, "y": 0, "rotation": 0, "z": 12,
  "createdAt": "…", "author": "user_…", "remember": null }
```
`x` and `y` are unbounded page coordinates in logical px, since the page is endless.

| type | extra fields |
|---|---|
| `stroke` | `tool` (pen/marker), `color`, `width`, `points: [[x,y,pressure,tMs], …]`, `arrow: {start?, end?, style}`, `straightened?: "line"/"circle"/…` |
| `shape` | `kind` (line/rect/ellipse/triangle/arrow), `w`, `h`, `stroke`, `fill` |
| `text` | `w`, `text`, `font`, `size`, `color` |
| `sticky` | `w`, `h`, `color`, `items` (nested ink/text), `stack?: {count}` |
| `frame` | `w`, `h`, `paper` (lined-a4, grid…), `title` |
| `image` | `w`, `h`, `asset`, `crop?` |
| `file` | `w`, `h`, `asset`, `mime` (pdf/docx/pptx/xlsx), `page?` |
| `embed` | `w`, `h`, `url` (website) |
| `math` | `w`, `h`, `latex`, `sourceStrokes?: [id]` |
| `graph` | `w`, `h`, `mode` (2d/3d), `functions: [{expr, color}]`, `view` |
| `table` | `w`, `h`, `cells: [[…]]`, `header` |
| `chart` | `w`, `h`, `chartType`, `source: {kind: table/xlsx, ref, range}`, `linked: true`, `snapshot?` |
| `widget` | `w`, `h`, `widget` (calendar/planner/flashcards/remember/clock/date/checklist/numberline/unitcircle/polar), `config` |
| `audio` | `asset`, `durationMs`, `inkTimeline: [{strokeId, tMs}]`, `transcript?: [{tMs, speaker, text}]` |
| `video` | `w`, `h`, `asset` or `remoteUrl`, `pins: [{tMs, itemId}]` |
| `timestamp` | `at` (ISO), `display` (clock/ago) |
| `checklist` | `w`, `title`, `entries: [{text, done}]` |

**Strokes, as implemented (v1):** `x`/`y` is the top-left of the stroke's points, and each point's `x`/`y` is relative to it, so moving a stroke only changes `x`/`y`. `tMs` is milliseconds since the stroke started (`createdAt` gives the absolute time). `pressure` is normalized to 0–1. `width` is the nominal width in page px at medium pressure. Two extra stroke fields: `penType` (`ballpoint`/`fountain`/`pencil`) and `usePressure` (false when "Pressure changes thickness" was off).

`remember` is either `null` or `{ "why": "...", "remindAt": "...", "flashcard": false }`.

## Rules
- Unknown item types and fields must be kept on load and written back on save, so newer files survive older apps.
- Stroke points are stored as flat numbers rounded to 0.1 px. A future binary encoding can come in v2.
- Sync merges at item level by `id`, so two devices never overwrite each other's strokes.
