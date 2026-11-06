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
│   ├── <sha256>.pdf     # an imported PDF; its pages' pictures are .png
│   ├── <sha256>.jpg.enc # the same, sealed, on a locked page or notebook
│   └── ...
├── study.json           # optional: how well each flashcard is known (FSRS)
└── index/
    └── recognition.json # optional cache: handwriting text per stroke group
```

Locked notebooks and pages store `pages/<pageId>.json.enc` (AES-256-GCM) in place of the plain file, along with `lock.json` (salt, Argon2id parameters, hint). See [Locks](#locks).

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
  "locked": false,
  "pinned": false,
  "trashedAt": null,
  "saveTo": "google"
}
```
`locked` means the whole notebook has a password. `pinned` shows it under Pinned on the Start page. `trashedAt` is set while it's in the Trash (it is deleted 30 days later). `saveTo` (optional, Update 02) is where the notebook is saved: `device` (this tablet only, never synced), `google` (Google Drive) or `onedrive`. A notebook without it, from before there was a choice, goes to every cloud that's on. It syncs like the other fields, so every device knows where the notebook goes.

## pages/<pageId>.json
```json
{
  "id": "pg_03",
  "title": "Lecture 3 — Momentum",
  "color": "#2B5A8C",
  "paper": "dots",
  "template": null,
  "locked": false,
  "spelling": { "ignore": ["Feynman"] },
  "items": [ /* Item[] in z-order */ ]
}
```
`color` (optional) is the page's color in the page bar and the All pages strip, stored like an ink color (dark mode brightens it for display); no color leaves it out. `template` is a built-in layout drawn under the ink (`cornell`, `meeting`, `weekly`, `todo`, `kanban`, `mind`, `story`, `lab`), or null. `paper` is `dots`, `lines`, `grid` or `blank`. `locked` means the page has its own password. `spelling.ignore` (optional) lists words spell check was told to ignore on this page; it is kept in the page file, so a page with a password keeps them sealed. Words added to "my dictionary" are the user's, for every notebook, and live in the app's settings, not in the package.

## Items
Every item has these fields:
```json
{ "id": "it_…", "type": "…", "x": 0, "y": 0, "rotation": 0, "z": 12,
  "createdAt": "…", "author": "user_…", "remember": null }
```
`x` and `y` are unbounded page coordinates in logical px, since the page is endless.

`items` is the z-order: later items draw on top. For every type with `w` and `h` (a box), `x`/`y` is the top-left corner before rotation, and `rotation` is in degrees, clockwise, about the box's center.

| type | extra fields |
|---|---|
| `stroke` | `tool` (pen/marker), `color`, `width`, `points: [[x,y,pressure,tMs], …]`, `arrow: {start?, end?, style}`, `straightened?: "line"/"circle"/…`, `startItemId?`, `endItemId?` |
| `shape` | `kind` (line/rect/ellipse/triangle/arrow), `w`, `h`, `stroke`, `fill`, `strokeWidth` |
| `text` | `w`, `text`, `font`, `size`, `color`, `autoWidth?` |
| `sticky` | `w`, `h`, `color`, `items` (nested ink/text), `stack?: {count, notes?}` |
| `sticky-pad` | `w`, `h`, `color` |
| `frame` | `w`, `h`, `paper` (lined-a4, grid-a4, dots-a4, blank-a4), `title`, `template?`, `unit?` |
| `image` | `w`, `h`, `asset`, `crop?` |
| `file` | `w`, `h`, `asset`, `mime` (pdf/docx/pptx/xlsx), `page?`, `preview?`, `name?`, `text?`; Office files also `pages`, `pageSize?`, `unit`, `ink?` |
| `embed` | `w`, `h`, `url` (website), `title`, `unit` |
| `kanban` | `w`, `h`, `title`, `unit`, `columns: [{title, cards: [{text}]}]` |
| `timeline` | `w`, `h`, `title`, `unit`, `events: [{date, label, state}]` |
| `diagram` | `w`, `h`, `title`, `unit`, `nodes: [{id, text, shape, color}]`, `edges: [{from, to}]` |
| `math` | `w`, `h`, `latex`, `size`, `color` |
| `graph` | `w`, `h`, `unit`, `mode` (2d/3d), `functions: [{expr, color, hidden?, ink?}]`, `view: {xMin, xMax, yMin, yMax}`, `trace?: {fn, x}`, `surfaces?: [{expr, color, hidden?}]`, `view3d: {turn, tilt, zoom, style}` |
| `table` | `w`, `h`, `title`, `unit`, `cells: [[…]]`, `header` |
| `chart` | `w`, `h`, `unit`, `title`, `chartType` (bar/line/area/scatter), `source?: {kind: table/xlsx, ref, sheet?, range?, name}`, `linked`, `snapshot: {cells}`, `colors?`, `suffix?` |
| `widget` | `w`, `h`, `widget` (calendar/planner/flashcards/remember/clock/date/numberline/unitcircle/polar), `config`, `unit` |
| `flashcard` | `deck`, `deckName`, `reverse`, `front: {ids?, text?}`, `back: {ids?, text?}` (not drawn; see below) |
| `audio` | `w`, `h`, `unit`, `asset`, `name`, `recordedAt`, `durationMs`, `wave`, `inkTimeline: [{strokeId, tMs}]`, `transcript: [{tMs, endMs, speaker?, text}]`, `speakers?`, `language?`, `transcribe?` (see below) |
| `video` | `w`, `h`, `unit`, `asset` or `link`, `name`, `durationMs`, `videoW`, `videoH`, `preview?`, `sound?`, `trimFrom?`, `trimTo?`, and a transcript as `audio` has (see below) |
| `video-pin` | `w`, `h`, `video` (its item id), `tMs` |
| `timestamp` | `w`, `h`, `unit`, `at` (ISO), `display` (clock/ago) |
| `checklist` | `w`, `h`, `unit`, `title`, `entries: [{text, done, ink?}]` |

**Strokes, as implemented (v1):** `x`/`y` is the top-left of the stroke's points, and each point's `x`/`y` is relative to it, so moving a stroke only changes `x`/`y`. `tMs` is milliseconds since the stroke started (`createdAt` gives the absolute time). `pressure` is normalized to 0–1. `width` is the nominal width in page px at medium pressure. Two extra stroke fields: `penType` (`ballpoint`/`fountain`/`pencil`) and `usePressure` (false when "Pressure changes thickness" was off).

- `arrow` is present only on arrows: `{"start": true, "end": true, "style": "open"}`, with `start`/`end` written only when true and `style` one of `open`, `filled`, `ink`. The heads are not points; they are drawn from the first/last points, the stroke's color and `width`.
- `straightened` is present only when a hold (or "Straighten lines") turned the stroke into a shape: `line`, `circle`, `ellipse`, `rect` or `triangle`. The points are the shape itself.
- `startItemId` / `endItemId` are present only on a connector (an arrow or a straightened line) whose first / last point is attached to the edge of a box item on the same page (a shape, sticky note, frame, picture, text box or card). The point itself lies on that item's outline; where on the edge is not stored separately, it is read from the point. When the item moves, turns or is resized, the end goes to the same spot of its edge and the ink bends to follow (each point moves by a share of the end's move that follows how far along the line it is). An attached end without an arrowhead is drawn with a dot. If the item is gone, the id is dropped; an id that names nothing is ignored.
- Moving, resizing and rotating a stroke rewrites its points (and scales `width`); `rotation` stays 0 for strokes.

**Math, graphs and math tools, as implemented (v1, Phases 6a and 6b):**

- `math`: `latex` is the math as LaTeX (the KaTeX subset `flutter_math_fork` draws). It is drawn on a card: typeset at `size` (page px), in `color` (an ink color, brightened in dark mode like ink), with padding of 0.44 × `size` left and right and 0.25 × `size` above and below. `w` and `h` (the card) are stored because typesetting is asynchronous. The math is fitted into the box, so a file from another device with slightly different font metrics still draws in its place. Scaling by a corner scales `size` with the box. Search finds math by its keyboard text (`ω = Δθ / Δt`) and the names of its Greek letters.
- `graph` (Phase 6b, Graph.png):
  - `mode` is `2d` or `3d`.
  - `unit` is the card's scale: its parts are Graph.dc.html's sizes (an 860 × 660 card) × `unit`. New graphs are written with `unit: 1`; a Phase 6a file without it is read as `w / 860`. Scaling by a corner changes `w`, `h` and `unit`; stretching an edge changes only `w` or `h`, and the plot takes the room.
  - `functions: [{expr, color, hidden?, ink?}]`:
    - `expr` is LaTeX for a function of x: `y = …`, `f(x) = …` or just the expression. A function that can't be evaluated is listed but not drawn.
    - `hidden: true` is listed but not drawn.
    - `ink` is a small copy of the handwriting it was graphed from: strokes as flat `[x, y, x, y, …]` lists in page px from the writing's top-left, at most 40 points a stroke. It is shown beside it as "from your handwriting"; changing the function drops it.
  - `view: {xMin, xMax, yMin, yMax}` is the 2D window.
  - `trace: {fn, x}` (optional) is the point being traced: the `fn`th function at `x`.
  - `surfaces: [{expr, color, hidden?}]` (optional) is what 3D shows: surfaces `z = …` (or `f(x, y) = …`, or an expression in x and y) over x and y from −3 to 3, and points `(x, y, z)`.
  - `view3d: {turn, tilt, zoom, style}` is the 3D view: degrees about the z axis and above the x–y plane (default 35 and 25), a zoom, and `wireframe` or `surface`.
  - The window, trace, mode, `hidden` and `view3d` change without an undo step (they're where you're looking, like an Office file's page). Functions and surfaces added, changed or taken off are undo steps.
- `widget` with `widget: numberline`, `unitcircle` or `polar` (Phase 6b, MathKit.png): the math tools. `unit` is the tool's scale (MathKit.dc.html's sizes × `unit`). `config` holds what it shows, and unknown fields in `config` are kept. A `widget` of a kind this version doesn't know is kept as it is, unread.
  - `numberline`: `config: {points: [{value, color}], intervals: [{from, to, openFrom, openTo, color, hidden?}]}`. `value`, `from` and `to` are LaTeX numbers (`-2.5`, `\sqrt{2}`, `\pi`), and an interval's end may be `\infty` or `-\infty` (always open). The line runs from −5 to 5, or further to show every number. Opening or closing an end is an undo step; hiding an interval isn't.
  - `unitcircle`: `config: {step}`, which of the 16 special angles is shown, from 0 (0°) to 15 (330°). Stepping isn't an undo step.
  - `polar`: `config: {curves: [{expr, color, hidden?}]}`, each `expr` LaTeX for r as a function of θ (`r = 1 + \cos\theta`; `r = 2` is a circle). The outer ring is 2, or the largest r shown, rounded up.

**Charts and live items, as implemented (v1, Phase 7b: Charts.png, LiveItems.png):**

```json
{ "id": "it_…", "type": "chart", "x": 540, "y": 96, "rotation": 0, "z": 9, "w": 700, "h": 404, "unit": 1,
  "title": "Momentum before vs. after", "chartType": "bar",
  "source": { "kind": "xlsx", "ref": "it_labdata", "sheet": "Sheet1", "name": "Lab data.xlsx" },
  "linked": true,
  "snapshot": { "cells": [["Trial", "p before", "p after"], ["1", "1.00", "0.97"], …] },
  "colors": ["#2B5A8C", "#B5532A"], "suffix": "" }
```

- `chart`:
  - `source` names what the numbers come from: a `table` item or an Excel `file` item (`xlsx`) **on the same page**, by its `ref` (item id). `sheet` is the Excel sheet's name (absent: the first sheet); `range` is cells like `A1:C7` (absent: everything in the table or sheet, so it grows with it). `name` is what the source was called when it was last read ("Lab data.xlsx", "Study hours"), for the link's label.
  - `snapshot.cells` is the range as it was last read, rows of cells as shown. **It is what's drawn**, so a chart draws without its source loaded, with its source deleted, and in other apps. Unknown fields in `snapshot` and `source` are kept.
  - While `linked` is true, any change to the source (a table edited, an Excel card given a newer version of its file, a renamed table) rewrites `snapshot.cells` and `source.name` **in the same undo step** as the change. Deleting the source sets `linked` false in the same step (Undo links it again). Unlink (snapshot) sets `linked` false; the chart keeps its numbers. A chart without `source` is a snapshot from somewhere else.
  - How the cells are read: a first row with words in it names the series; the first column labels the groups (words, or numbers under a name: "Trial" over 1, 2 reads "Trial 1", "Trial 2"); with more columns of numbers than rows, each row is a series, otherwise each column is. Numbers may have thousands commas, a currency sign, % or a short unit ("2 h").
  - `chartType` is how it's drawn; changing it isn't an undo step. `colors` are the series' colors in order, stored like ink (brightened in dark mode); series past the end take the graph colors. `suffix` follows the numbers on the axis and the total ("h").
  - `unit` is the card's scale (Charts.dc.html's sizes × `unit`). A chart at least 300 × `unit` tall shows the first header (title, link, chart type and Data); a shorter one the second (title, link, total).
- `widget` with `widget: clock`: `config: {style: analog/digital}`, a clock in the device's time zone, drawn for the moment it's drawn. With `widget: date`: today's date on a chip. Their `w` and `h` follow from what they show × `unit` (280 × 330 analog, 280 × 148 digital, 236 × 32 for the date); they scale and don't stretch. Analog or Digital isn't an undo step. Unknown fields in `config` are kept.
- `widget` with `widget: calendar`, `planner`, `flashcards` or `remember` (Phase 7c, WidgetBoard.png): live widgets. They hold a reference, never a copy: what they show comes from the app's calendar, planner and study data when they're drawn, so another device draws them with its own. Their size is fixed × `unit` (they scale and don't stretch). Unknown fields in `config` are kept.
  - `calendar`: `config: {view: month/agenda, hidden?: [calendarId]}`, 370 × 364. The month (six weeks, Sunday first) with a dot for each calendar with events that day and today's events, or what's coming up in the next two weeks. It shows the calendars shown in the Calendar, but `hidden`. Month or Agenda isn't an undo step; Calendars is.
  - `planner`: `config: {range: today/three/week}`, 450 × 380: today's schedule and to-dos, 3 days, or the week with its goals. The range isn't an undo step; ticking a to-do changes the planner, not the page.
  - `flashcards`: `config: {deck, deckName}`, 250 × 260: the next card due in the deck (from decks.json), to flip and answer (Again, Got it), and Study all. `deckName` is kept for a device without the deck. Flipping isn't saved.
  - `remember`: `config: {folder?: [path]}`, 544 × 160: the three newest things to remember in that folder (or everywhere), and See all.
- `timestamp`: `at` is the moment it was made (UTC); `display` is `clock` ("8:36 PM", in the device's time zone) or `ago` ("12 min ago"). 108 × 26 × `unit`. Switching between them (all the page's stamps at once) isn't an undo step.
- `checklist`: `w` is its width (400 × `unit` new); its height follows from its rows (`h` is written for other readers). Each entry has typed `text` and/or handwritten `ink` (strokes from the top-left of the entry's writing area, past its box, at 100%), and `done`. Ink written on a row belongs to that entry; ink written on "write another item…" starts a new one. Ticking is an undo step. An entry whose ink is all erased goes when the eraser lifts. Unknown fields in entries are kept.

**Text, sticky notes, frames, images and shapes, as implemented (v1):**

- `text`: `w` is where the text wraps. `font` is `ui` (Figtree), `serif` (Newsreader) or `hand` (Caveat); `size` is in page px with a line height of 1.3. With `autoWidth: true` (a new box, until it is stretched to a width) the box hugs the text and `w` is only the most it may grow to. The height is not stored; it follows from the text.
- `sticky`: `color` is the paper (`#F6DE7A` yellow, `#F3CBD6` pink, `#F4C9A8` peach, `#C9DFC2` green). `items` holds the ink written on the note and at most one `text` item for typed text, with `x`/`y` relative to the note's top-left corner (before its rotation), so they move, turn and scale with it. What's on a note is clipped to it, and keeps its own colors in dark mode.
- A stack is a sticky with `stack: {"count": 5, "notes": [{"color": "#F4C9A8", "items": []}, …]}`. The sticky itself is the top note; `notes` are the ones under it, from just under the top down. `count` is the top note plus `notes`; if `count` is larger (a file that only says how many), the missing notes are blank.
- `sticky-pad`: a pad of sticky notes. Nothing is written on it and it holds nothing: each note dragged off it becomes a new `sticky` of the pad's `w`, `h`, `color` and `rotation`, and the pad stays as it was. It is drawn as its top sheet with the pad's edge showing under it (about 9 px at 176 px wide, scaling with it).
- `frame`: a sheet of paper drawn under the ink. A lined A4 sheet is 560 × 792 px at 100%, ruled every 40 px from y = 96, with a margin at x = 80. `title` is the name shown above it ("Frame · Lab 4"); empty shows the paper's name ("Frame · Lined A4"). `template` is a built-in template id (`cornell`, `weekly`…) whose layout is drawn on the sheet, scaled to its width. `unit` (default 1) is how much the sheet has been scaled: its rules are 40 × `unit` apart. Ink written on a frame is ordinary page ink above it in `items`; it is not nested.
- `image`: `asset` is the file's name in `assets/`, `<sha256 of the file>.<png|jpg|gif|webp|bmp>`. The same picture added twice is stored once. `crop` is kept but not used yet.
- `shape`: `stroke` and `fill` are colors (`fill` null for none); `strokeWidth` is in page px. A `line` or `arrow` has `h: 0` and runs along the middle of its box from the left edge to the right, so its direction is `rotation`; the arrowhead is at the right end.

**Cards built on the board, as implemented (v1):** `kanban`, `timeline`, `diagram`, `table` and `embed` are boxes with a header. `title` is the name in the header (empty shows what it is; a website shows its host). `unit` is the card's scale: its text and spacing are the design's sizes (Board.dc.html) × `unit`. New cards are written with `unit: 1.375`; a file without it is read as 1. Scaling a card by a corner changes `w`, `h` and `unit` together; stretching an edge changes only `w` or `h`, and what's inside reflows. Unknown fields inside columns, cards, events and nodes are kept.

- `kanban`: `columns` in order, each with a `title` and its `cards` (`{"text": "…"}`). Cards in the last column are shown done (struck through), and those in the columns between the first and the last as in progress.
- `timeline`: `events` in order. `date` is the text shown ("Sep 30"), `label` what happens, and `state` is `done`, `now` (up next) or `later`.
- `diagram`: `nodes` are laid out in order, left to right, wrapping into rows. `shape` is `box`, `pill` or `diamond`; `color` is `blue`, `clay`, `green` or `plum` (a palette role, so it follows the theme). `edges` are arrows from one node `id` to another; the app's own diagrams join each node to the next.
- `table`: `cells` is rows of strings. `header: true` means the first row is the column names.
- `embed`: `url` is the page's address. Only `http` and `https` addresses are ever opened.

**Imported files, as implemented (v1):** a `file` item is one page of a file, written on like a picture (ink on it rides along when it moves).

- `asset` is the file itself in `assets/` (`<sha256>.pdf`), stored once however many pages use it. `page` is which page, from 1. `mime` is `pdf` for now.
- `preview` is a PNG of the page made when it was imported (`<sha256>.png`, 2 px per PDF point, at most 4096 px on its longest side). The canvas, thumbnails and exports draw it; the PDF itself isn't read again.
- `w` and `h` are the page's size in PDF points: one point is one page px. An imported PDF page sits at `x: 0, y: 0`, one per notebook page, under what is written on it.
- `name` is the file's name when it was imported. `text` is the page's own text (what PDFium reads), kept so it stays searchable; it goes into an exported PDF's invisible text layer.
- Like an `image`, its files are sealed (`.enc`) on a page with a password.

**Word, PowerPoint and Excel files, as implemented (v1):** a `file` item with `mime` `docx`, `pptx` or `xlsx` is a card on the board with a live preview of one page, slide or sheet (Board.dc.html: the DOCX, PPTX and XLSX cards). The app reads the file itself to draw it; nothing drawn from it is stored.

```json
{
  "id": "it_01J…", "type": "file", "x": 300, "y": 120, "rotation": 0, "z": 7,
  "w": 495, "h": 378, "asset": "9f2c…e1.pptx", "mime": "pptx", "name": "Ch 9 slides.pptx",
  "page": 3, "pages": 24, "pageSize": [960, 540], "unit": 1.375,
  "ink": { "3": [ { "id": "it_…", "type": "stroke", … } ] }
}
```

- `asset` is the file in `assets/`, `<sha256 of the file>.<docx|pptx|xlsx>`, byte for byte as it was added, stored once however many cards use it. Like pictures, it is sealed (`.enc`) on a page with a password and is part of a board file. A newer version of the file (saved in its own app after Open, or Replace file) is stored as a new asset and the card's `asset`, `pages`, `pageSize`, `page` and `ink` change together; the old file stays, for Undo.
- `page` is the page, slide or sheet showing, from 1; `pages` how many there were when it was last read. Stepping through them changes `page` without an undo step.
- `pageSize` is a Word page or a slide in points (`[612, 792]` for Letter, `[960, 540]` for a 16:9 deck). It is absent for Excel.
- `unit` is the card's scale, as for the cards built on the board: its header (38 px), footer (36 px, shown for PowerPoint and whenever there's more than one page or sheet) and text are the design's sizes × `unit`.
- `ink` holds the ink written on each page, keyed by page number as a string. Strokes are in the page's own coordinates: points of `pageSize` for Word and PowerPoint (so ink stays on its words however the card is moved, scaled or stretched), and the card's px before `unit` for Excel, from the top-left of the cells. Only the showing page's ink is drawn; it is clipped to the card between its header and footer.
- When the card gets a newer version of its file, each page's ink moves to where that page is now: slides by their `p:sldId` and sheets by their `sheetId`, so ink follows a slide that was moved, and goes with one that was deleted. Word pages keep their numbers.
- Ink written beside a card is ordinary page ink.

**Need to remember, as implemented (v1, Phase 7a, RememberMark.png):** `remember` is `null`, or the item is marked to remember:

```json
"remember": { "id": "rm_01J…", "why": "always on the exam", "remind": "tomorrow",
              "remindAt": "2026-09-26T07:00:00.000Z", "flashcard": "fc_01J…", "at": "2026-09-25T10:00:00.000Z" }
```

- Items with the same `id` are **one thing to remember**: what was lassoed together, or a drawn star and what it was drawn next to. A mark without an `id` (an older file's `{why, remindAt, flashcard: false}`) is a thing of its own, named after its item.
- `why` (optional) is "Why it matters".
- `remind` is how the reminder was picked: `tomorrow` (9 in the morning, the device's time), `date` (a date and time picked) or `event` (before a calendar event). `remindAt` is when it goes off, in UTC. Neither is written when there's no reminder.
- With `remind: event`, `event: {id, day, title, before}` names the event (its id in the app's calendar.json), the day it happens on (`2026-09-25`; a repeating event happens on many), its title when it was picked, and how many minutes before it. If the event moves, the reminder moves with it; if it's gone, or on a device without it, the reminder goes off at `remindAt`. An all-day event counts as starting at 9 in the morning.
- `flashcard` is the id of the `flashcard` item made from it ("Also make it a flashcard"). `drawn: true` means it was marked by drawing a star; the star stroke itself carries the same mark with `star: true` and is not part of what's remembered. `at` is when it was marked.
- Marking, changing and forgetting are item edits, so they are undo steps, are sealed with a page that has a password, and go along in board files. A copy of a marked item isn't marked.
- Reminders are local notifications on the device, set from these marks (nothing leaves the device). A page or notebook with a password is never read for them, so its reminders don't go off while it has one.

**Recordings, as implemented (v1, Phase 8a, Audio.png):** an `audio` item is a recording's card on the page.

```json
{ "id": "it_01J…", "type": "audio", "x": 110, "y": 520, "w": 560, "h": 152, "unit": 1, "rotation": 0, "z": 12,
  "asset": "<sha256>.m4a", "name": "Lecture 3 recording", "recordedAt": "2026-11-06T12:10:00.000Z", "durationMs": 2900000,
  "wave": [0, 12, 40, …], "inkTimeline": [{ "strokeId": "it_…", "tMs": 760000 }],
  "transcript": [{ "tMs": 722000, "endMs": 744000, "speaker": "s1", "text": "Okay, so last time…" }],
  "speakers": { "s1": "Professor" }, "language": "en" }
```

- `asset` is the recording in `assets/`: AAC in an `.m4a` (16 kHz mono, 32 kbit/s, about 14 MB an hour) from Android, a 16-bit `.wav` where AAC isn't recorded. Sealed (`.enc`) on a page with a password, like pictures, and part of a board file.
- The card is Audio.dc.html's section: 560 × 152 at `unit: 1`. Scaling it by a corner changes `unit` (`w` and `h` follow). `name` is shown on it (the page's title + " recording", or "Recording", "Recording 2"); `recordedAt` and `durationMs` give "Fri · 48:20".
- `wave` is how loud it was along the recording, 120 values from 0 to 100 (the loudest in each stretch), for the card's waveform.
- `inkTimeline` lists the strokes written (on any page of the notebook) while it recorded, and when: ms into the recording, not counting pauses. Strokes that are gone are ignored. A copy of the card isn't linked to the ink (its `inkTimeline` is empty).
- `transcript` is what was said, a line at a time, made on the device. `speaker` is a key (`s1`, `s2`, … in the order they first speak), absent when not known; `speakers` holds the names given to them (unnamed ones show as "Speaker 2"). `language` is the language heard, as a code.
- Lines can be edited (an undo step): the text changes, `tMs`, `endMs` and `speaker` stay; a line emptied is removed.
- `transcribe` is present only while the transcript isn't finished: `{"state": "waiting" | "working" | "failed", "upToMs": 240000}`. `upToMs` is how far the words have got; the transcript carries on from there. Saving the transcript as it's made isn't an undo step, and Undo keeps it.
- In a PDF the card is a picture and its transcript is in the text layer. Search finds each line of the transcript.

**Videos, as implemented (v1, Phase 8b, Video.png):** a `video` item is a video's card on the page (700 × 490 at `unit: 1`).

- The file is `asset` (in `assets/`, up to 100 MB; sealed on a page with a password, up to 200 MB) or, for a bigger one, `link`: a file name in the device's own videos folder (`<app support>/videos/`), not in the package. A board file carries an asset, not a linked file; on another device a linked video shows its still and can't play unless it's in the cloud.
- `cloud` (Phase 9a): where a big video was moved to, `{"in": "google" | "onedrive", "path": "Videos/vid_….mp4", "size": 734003200}`, the path inside the sync folder. Once it's there the device's own copy goes; it plays from the cloud (through the app's local media server, which adds the sign-in), and is fetched into `<app support>/videos/cloud/<link>` when a frame, the trim strip or a transcript needs the file. `link` stays as the name it's kept under. Any device signed in to that cloud can play it.
- `preview` is a still from it (a JPEG in `assets/`), drawn until it plays and in exports. `videoW` × `videoH` is its shape as shown. `sound: false` when it has no sound.
- `trimFrom` / `trimTo` (ms) are where it starts and stops playing; absent is its start and end. The file isn't cut.
- `transcript`, `speakers`, `language` and `transcribe` are as for `audio` (see Recordings), with one difference: a video without `transcribe` has **never been transcribed**; a transcript asked for is written with `transcribe: {"state": …}`, `done` included.
- Times everywhere (pins, the transcript) are the video file's own, whatever the trim.
- A `video-pin` is a "▶ 0:12" chip: a note pinned to moment `tMs` of the video `video` on the same page. It's an orange dot on that video's timeline (when within its trim). The note is what's written beside it. A pin whose video is gone is kept, and does nothing.
- An `image` with `caption` (a string, kept in its fields) is drawn on a white card with the caption under it: a frame grabbed from a video ("Grabbed frame · from video").

**Flashcards, as implemented (v1, Phase 7a, FlashMake.png):** a `flashcard` item is a card made on its page. It isn't drawn, can't be selected, and isn't exported to PDF; `x`/`y` is where its front was when it was made.

```json
{ "id": "fc_01J…", "type": "flashcard", "x": 150, "y": 196, "rotation": 0, "z": 31, "createdAt": "…",
  "deck": "dk_01J…", "deckName": "Physics — Momentum", "reverse": true,
  "front": { "ids": ["it_a"] }, "back": { "ids": ["it_b", "it_c"], "text": "a push over a time" } }
```

- `front` and `back` name items on the same page by id (what was circled: ink, pictures, text boxes, anything), so the card shows them as they are now. `text` is typed text on that side (a dictionary word's definition, a "why it matters"). A side whose items were all erased says so when studied.
- `deck` is the deck's id; `deckName` its name when the card was made, so a board file brings its deck along (the deck list is the app's `decks.json`, below).
- `reverse: true` is "Also quiz me back to front": the card is asked both ways, each with its own schedule.
- Adding and deleting a card are undo steps.

## study.json
How well each flashcard of the notebook is known, from FSRS-6 (py-fsrs 6.3.2's default weights, learning steps of 1 and 10 minutes, a relearning step of 10 minutes, 90% retention, no fuzz). A card never studied has no entry: it is new, and due.

```json
{ "version": 1, "cards": {
    "fc_01J…": {
      "f": { "phase": "review", "s": 10.971, "d": 2.1043, "due": "2026-10-08T10:10:00.000Z", "last": "2026-09-27T10:10:00.000Z", "reps": 3, "lapses": 0 },
      "r": { "phase": "learning", "step": 1, "s": 2.3065, "d": 2.1181, "due": "2026-09-25T10:10:00.000Z", "last": "2026-09-25T10:00:00.000Z", "reps": 1, "lapses": 0 } } } }
```

`f` is front to back, `r` back to front. `phase` is `learning`, `review` or `relearning`; `step` the learning or relearning step (absent in review); `s` stability in days; `d` difficulty from 1 to 10; `due` and `last` (the last review) in UTC. Unknown entries are kept. It is written as cards are rated, not on a timer, and isn't an undo step. It holds no content, so it is never sealed.

## Locks
`lock.json`:
```json
{
  "version": 1,
  "notebook": null,
  "pages": {
    "pg_03": {
      "kdf": { "alg": "argon2id", "memoryKiB": 19456, "iterations": 2, "parallelism": 1 },
      "salt": "<16 bytes, base64>",
      "check": "<sealed \"endless-lock-check\", base64>",
      "hint": "units",
      "biometric": true
    }
  }
}
```
- A page with its own entry uses that password; any other page of a notebook with a `notebook` entry uses the notebook's.
- The key is Argon2id(password, salt), 32 bytes. `check` tells a wrong password from a damaged file.
- A sealed file is `EBL1` (4 bytes) · nonce (12) · GCM tag (16) · ciphertext of the page JSON.
- The password and key are never written. `biometric` means this device keeps the key in the platform's secure storage for fingerprint or face unlock.
- Order of writes: lock.json before the first sealed page; when a lock is removed, the plain page before lock.json loses the entry. If both `pages/<id>.json` and `.json.enc` exist, the sealed one wins.
- Images on a page with a password are sealed the same way, with the same key, as `assets/<name>.enc` (the item's `asset` stays `<name>`). When a page is locked, its images are sealed and their clear copies deleted, along with any clear image no unlocked page still uses; when the password is removed they are written in the clear again.

## index/recognition.json
What the handwriting says, kept so it is read once (Phase 5). It is a cache: deleting it only means the handwriting is read again. Only pen ink is read (not highlighter, shapes a hold made, arrows or connectors), a line at a time: on the page itself, on sticky notes (each note of a stack too), on every page, slide or sheet of an Office card, and on checklists.
```json
{
  "version": 1,
  "pages": {
    "pg_03": {
      "lang": "en-US",
      "lines": [
        {
          "key": "9f2c41aa07d3e6b1",
          "strokes": ["st_a", "st_b", "st_c"],
          "text": "total momentum is conserved",
          "block": 1,
          "words": [
            {"t": "total", "s": ["st_a"]},
            {"t": "momentum", "s": ["st_b"]},
            {"t": "is", "s": ["st_c"]},
            {"t": "conserved", "s": ["st_d", "st_e"], "alts": ["conversed", "concerned"]}
          ]
        }
      ]
    }
  }
}
```
- `holder` (omitted for ink on the page) is the sticky note, Office card or checklist the line is written on, in that item's own coordinates (a checklist's: where its rows are on the card, at 100%). `sub` is which page, slide or sheet of the Office file (from 1), or which note under a stack's top one (from 1); omitted for a top note.
- `lang` is the ML Kit language tag it was read in. `strokes` are the line's stroke ids in pen order; `block` is its paragraph on the page, counting from 0 in reading order.
- `key` is a hash (FNV-1a, 64-bit, hex) of the language and, per stroke, its id, point count, size and place relative to the line's first stroke. The same ink, moved anywhere on the page, has the same key, so its text is reused; any change to its strokes reads it again.
- `words` tie each word to the strokes that wrote it (`s`, empty when the line's gaps didn't match its words), and `alts` lists other readings when recognition wasn't sure (for Convert to text).
- **Never holds a page with a password.** A page or notebook that gets one loses its entries at once, and nothing is written for it while it has one.

## Export and import
A `.board` file is the package zipped, with `notebook.json` at the top of the zip (a zip holding one `<name>.board/` folder is read too). Pictures and PDFs are stored without compressing them again.

- **Export** writes what is on disk, after the open notebook is saved. Locked pages stay sealed (`.json.enc`), with their `lock.json` entries, so the password still protects them. Exporting some pages writes a `notebook.json` listing only those pages, only their entries in `lock.json`, and only the files their clear pages use (plus every sealed file, if a locked page goes along, since which pages use them can't be read without the password). Without images, `assets/` is left out and pictures show as empty boxes.
- **Import** makes a notebook. It keeps its `id` if no notebook on the device has it; if one in the library does, the app asks: **Replace** deletes that package and writes the file in its place (same `id`, keeping its folder and `pinned`), **Keep both** gives the import a new `id`. Either way it gets the folder picked in Import into (Replace: the one it was in), `pinned` false (Replace: as it was), `trashedAt` null, `updatedAt` now. Everything else in `notebook.json` and every page and item, ids included, comes in as it was. Only `notebook.json`, `lock.json`, `pages/<pageId>.json(.enc)` for page ids listed in `notebook.json` (letters, digits, `_` and `-`), `index/recognition.json`, `study.json`, and `assets/<name>` with a plain file name are read: nothing else in the zip is written anywhere. A page whose file is damaged comes in empty. Fingerprint unlock has to be turned on again for the copy.
- `index/recognition.json` goes along when "Include recognized handwriting text" is on (the default), with only the exported clear pages. Import keeps it for clear pages only, and not at all for a notebook with a password, so search works straight away.
- `study.json` goes along with the entries of the flashcards on the exported pages (all of them when a page with a password goes along, since its cards can't be told apart), and comes back on import, so studying carries on where it was.

## Sync (Phase 9a)
The copy in the cloud (Google Drive or OneDrive, in the folder picked in Settings › Sync & backup, "Endless Notebooks" to start with):

```
Endless Notebooks/
├── endless.json                      # folders, decks, notebooks deleted for good (below)
├── <title> · <notebookId>.board/
│   ├── notebook.json                 # as on the tablet, plus `sync`
│   ├── pages/<pageId>.<hash>.json    # a page, plus its stamps in `sync`
│   ├── pages/<pageId>.<hash>.json.enc
│   ├── lock.<hash>.json
│   ├── study.<hash>.json
│   └── assets/<name>                 # as on the tablet (named by content already)
├── PDF/<title> (<last 4 of id>).pdf  # only with "Also save a PDF copy"
└── Videos/<link>                     # big videos moved to the cloud
```

- **A notebook's folder is `<title> · <id>.board`**: the title so people can tell them apart in Drive or OneDrive (characters folders can't have removed, cut at 60), the id so Endless knows which notebook it is. Renaming the notebook renames its folder on the next sync. A folder named just `<id>.board` (before 2026-11-05) is read and renamed. If two folders hold the same notebook (two devices renaming at the same moment), one is synced and the other deleted; the device that wrote there still has its changes and sends them again.
- **Every file but `notebook.json` is named after its contents** (`<hash>` is the FNV-1a hash and length of the bytes), so no file is ever written over: two devices sending at the same moment can't replace each other's pages. `notebook.json` is written last and lists the rest, so whichever lands last describes a whole notebook. A device whose `notebook.json` was replaced sees on its next sync that the files listed aren't the ones it sent, and merges again. Files the new `notebook.json` no longer lists are deleted after it's written.
- **Stamps.** A stamp says when something last changed: `<ms, 15 digits>.<counter, 6 digits>.<device id>`, which sorts in time order. A change is stamped with the notebook's `updatedAt`, but always later than the stamp it replaces, so an edit made after seeing another device's change wins over it even with a slow clock.
- A page's `sync`: `{"page": stamp, "items": {itemId: stamp}, "gone": {itemId: stamp}}`: its own fields (title, paper, template, spell check's ignored words), each item, and items deleted.
- `notebook.json`'s `sync`: `{"v": 1, "fields": {name: stamp}, "gonePages": {pageId: stamp}, "sealed": {pageId: stamp}, "lockNotebook": stamp, "study": stamp, "files": {"pages/<pageId>.json": hash, "lock.json": hash, …}, "assets": [names in the cloud], "device": "Kim’s tablet"}`. `fields` covers every field but `id`, `format`, `version`, `createdAt` and `updatedAt` (the page order is the field `pages`).
- **Merging ("Merge both").** For each item, by `id`: the copy with the newer stamp; an item deleted on one device stays deleted unless it changed later on another (then it comes back). Notebook fields one by one, the same way. Pages added on either device are both kept, in the order of the device whose page order changed last, each added page after the page before it. A page deleted on one device stays deleted unless written on later. Items' order on a page: the copy changed last, with items only the other has after the item before them there. The merge gives the same notebook whichever order copies meet in. Fields and item types this version doesn't know travel untouched (merging works on the JSON).
- **Pages with a password** merge as a whole (their items can't be read without it): the sealed copy wins over a clear one unless the page itself changed later on the other device (its password removed); two sealed copies, the newer. A page's `lock.json` entry goes with its sealed copy; the notebook's password is the newer one's.
- **"Keep the newest"** (the other choice): the copy changed last replaces the other as a whole.
- `study.json`: the newer copy. `index/recognition.json` isn't synced: each device reads the handwriting itself.
- `endless.json`: `{"format": "endless.sync", "version": 1, "folders": Keyed, "decks": Keyed, "notebooks": Keyed}`, each `Keyed` being `{"values": {key: value}, "stamps": {key: stamp}, "gone": {key: stamp}}`: folders by `jsonEncode(path)` (`{path, color}`), decks by id (as in `decks.json`), and only deletions for notebooks (deleted for good, so no device brings them back).
- **On the device** (never in a package or a board file): `sync/settings.json` (Sync & backup's settings, this device's id, and when each notebook was last synced), `sync/nb_<id>.json` (a hash and stamp of each part of the notebook as last synced, so changes since are seen and stamped, and each cloud's file hashes as last seen there), `sync/root.json` and `sync/pdf.json`. Sign-ins that last (refresh tokens) are in the platform's secure storage.

## Version history (Phase 9a)
`versions/<notebookId>/<pageId>/<ms>-<why>[-<device>].json`, or `.json.enc` on a page with a password (sealed with the page's key): a page's file as it was. `why` is `edit` (kept while writing, at most every 10 minutes), `sync` (before another device's changes came in; `device` names it) or `restore` (before an earlier version was restored). Thinned out: everything from the last hour, one per 10 minutes for a day, one per day for a month, one per week after, at most 100 a page. On the device only; deleted with the notebook.

## Outside the packages
The app's data folder also holds `settings.json`, `library.json` (folders: `{"version": 1, "folders": [{"path": ["School", "Physics"], "color": "#2B5A8C"}]}`), `decks.json` (the flashcard decks: `{"version": 1, "decks": [{"id": "dk_…", "name": "Physics — Momentum", "createdAt": "…"}]}`; a card from another device adds its deck from its `deckName`), `templates/<id>.json` (My templates: `format: "endless.template"`, `name`, `paper`, `template`, `items`), `calendar.json` (the calendars and the events made here; a calendar link is a calendar with `kind: "feed"`, `from` (`google`, `outlook` or `web`), `fetchedAt` and `error`, whose events aren't stored but read again from `calendars/<id>.ics`, the last copy of the link's file; `links` maps such an event's id to its notes, `{notebook, page?}`; the link itself is in the platform's secure storage, never in a file), `planner.json` and `index.sqlite` (the library index and search index, and what's remembered and the flashcards on each page for the Remember and Flashcards screens: caches rebuilt from the packages).

## Rules
- Unknown item types and fields must be kept on load and written back on save, so newer files survive older apps. A known type whose fields can't be read (a missing `w`, a bad color) is kept as it is too.
- Stroke points are stored as flat numbers rounded to 0.1 px. A future binary encoding can come in v2.
- Sync merges at item level by `id`, so two devices never overwrite each other's strokes (see Sync).
