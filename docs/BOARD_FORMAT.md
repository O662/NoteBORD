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
  "trashedAt": null
}
```
`locked` means the whole notebook has a password. `pinned` shows it under Pinned on the Start page. `trashedAt` is set while it's in the Trash (it is deleted 30 days later).

## pages/<pageId>.json
```json
{
  "id": "pg_03",
  "title": "Lecture 3 — Momentum",
  "paper": "dots",
  "template": null,
  "locked": false,
  "spelling": { "ignore": ["Feynman"] },
  "items": [ /* Item[] in z-order */ ]
}
```
`template` is a built-in layout drawn under the ink (`cornell`, `meeting`, `weekly`, `todo`, `kanban`, `mind`, `story`, `lab`), or null. `paper` is `dots`, `lines`, `grid` or `blank`. `locked` means the page has its own password. `spelling.ignore` (optional) lists words spell check was told to ignore on this page; it is kept in the page file, so a page with a password keeps them sealed. Words added to "my dictionary" are the user's, for every notebook, and live in the app's settings, not in the package.

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
| `frame` | `w`, `h`, `paper` (lined-a4, grid-a4, dots-a4, blank-a4), `title`, `template?`, `unit?` |
| `image` | `w`, `h`, `asset`, `crop?` |
| `file` | `w`, `h`, `asset`, `mime` (pdf/docx/pptx/xlsx), `page?`, `preview?`, `name?`, `text?`; Office files also `pages`, `pageSize?`, `unit`, `ink?` |
| `embed` | `w`, `h`, `url` (website), `title`, `unit` |
| `kanban` | `w`, `h`, `title`, `unit`, `columns: [{title, cards: [{text}]}]` |
| `timeline` | `w`, `h`, `title`, `unit`, `events: [{date, label, state}]` |
| `diagram` | `w`, `h`, `title`, `unit`, `nodes: [{id, text, shape, color}]`, `edges: [{from, to}]` |
| `math` | `w`, `h`, `latex`, `size`, `color` |
| `graph` | `w`, `h`, `mode` (2d/3d), `functions: [{expr, color}]`, `view: {xMin, xMax, yMin, yMax}` |
| `table` | `w`, `h`, `title`, `unit`, `cells: [[…]]`, `header` |
| `chart` | `w`, `h`, `chartType`, `source: {kind: table/xlsx, ref, range}`, `linked: true`, `snapshot?` |
| `widget` | `w`, `h`, `widget` (calendar/planner/flashcards/remember/clock/date/checklist/numberline/unitcircle/polar), `config` |
| `audio` | `asset`, `durationMs`, `inkTimeline: [{strokeId, tMs}]`, `transcript?: [{tMs, speaker, text}]` |
| `video` | `w`, `h`, `asset` or `remoteUrl`, `pins: [{tMs, itemId}]` |
| `timestamp` | `at` (ISO), `display` (clock/ago) |
| `checklist` | `w`, `title`, `entries: [{text, done}]` |

**Strokes, as implemented (v1):** `x`/`y` is the top-left of the stroke's points, and each point's `x`/`y` is relative to it, so moving a stroke only changes `x`/`y`. `tMs` is milliseconds since the stroke started (`createdAt` gives the absolute time). `pressure` is normalized to 0–1. `width` is the nominal width in page px at medium pressure. Two extra stroke fields: `penType` (`ballpoint`/`fountain`/`pencil`) and `usePressure` (false when "Pressure changes thickness" was off).

- `arrow` is present only on arrows: `{"start": true, "end": true, "style": "open"}`, with `start`/`end` written only when true and `style` one of `open`, `filled`, `ink`. The heads are not points; they are drawn from the first/last points, the stroke's color and `width`.
- `straightened` is present only when a hold (or "Straighten lines") turned the stroke into a shape: `line`, `circle`, `ellipse`, `rect` or `triangle`. The points are the shape itself.
- `startItemId` / `endItemId` are present only on a connector (an arrow or a straightened line) whose first / last point is attached to the edge of a box item on the same page (a shape, sticky note, frame, picture, text box or card). The point itself lies on that item's outline; where on the edge is not stored separately, it is read from the point. When the item moves, turns or is resized, the end goes to the same spot of its edge and the ink bends to follow (each point moves by a share of the end's move that follows how far along the line it is). An attached end without an arrowhead is drawn with a dot. If the item is gone, the id is dropped; an id that names nothing is ignored.
- Moving, resizing and rotating a stroke rewrites its points (and scales `width`); `rotation` stays 0 for strokes.

**Math and graphs, as implemented (v1, Phase 6a):**

- `math`: `latex` is the math as LaTeX (the KaTeX subset `flutter_math_fork` draws). It is drawn on a card: typeset at `size` (page px), in `color` (an ink color, brightened in dark mode like ink), with padding of 0.44 × `size` left and right and 0.25 × `size` above and below. `w` and `h` (the card) are stored because typesetting is asynchronous. The math is fitted into the box, so a file from another device with slightly different font metrics still draws in its place. Scaling by a corner scales `size` with the box. Search finds math by its keyboard text (`ω = Δθ / Δt`) and the names of its Greek letters.
- `graph`: `mode` is `2d` (3D comes with the Graph screen). Each function's `expr` is LaTeX for a function of x: `y = …`, `f(x) = …` or just the expression. `view` is the window shown. A function that can't be evaluated is listed but not drawn.

**Text, sticky notes, frames, images and shapes, as implemented (v1):**

- `text`: `w` is where the text wraps. `font` is `ui` (Figtree), `serif` (Newsreader) or `hand` (Caveat); `size` is in page px with a line height of 1.3. With `autoWidth: true` (a new box, until it is stretched to a width) the box hugs the text and `w` is only the most it may grow to. The height is not stored; it follows from the text.
- `sticky`: `color` is the paper (`#F6DE7A` yellow, `#F3CBD6` pink, `#F4C9A8` peach, `#C9DFC2` green). `items` holds the ink written on the note and at most one `text` item for typed text, with `x`/`y` relative to the note's top-left corner (before its rotation), so they move, turn and scale with it. What's on a note is clipped to it, and keeps its own colors in dark mode.
- A stack is a sticky with `stack: {"count": 5, "notes": [{"color": "#F4C9A8", "items": []}, …]}`. The sticky itself is the top note; `notes` are the ones under it, from just under the top down. `count` is the top note plus `notes`; if `count` is larger (a file that only says how many), the missing notes are blank.
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

`remember` is either `null` or `{ "why": "...", "remindAt": "...", "flashcard": false }`.

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
What the handwriting says, kept so it is read once (Phase 5). It is a cache: deleting it only means the handwriting is read again. Only pen ink is read (not highlighter, shapes a hold made, arrows or connectors), a line at a time: on the page itself, on sticky notes (each note of a stack too), and on every page, slide or sheet of an Office card.
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
- `holder` (omitted for ink on the page) is the sticky note or Office card the line is written on, in that item's own coordinates. `sub` is which page, slide or sheet of the Office file (from 1), or which note under a stack's top one (from 1); omitted for a top note.
- `lang` is the ML Kit language tag it was read in. `strokes` are the line's stroke ids in pen order; `block` is its paragraph on the page, counting from 0 in reading order.
- `key` is a hash (FNV-1a, 64-bit, hex) of the language and, per stroke, its id, point count, size and place relative to the line's first stroke. The same ink, moved anywhere on the page, has the same key, so its text is reused; any change to its strokes reads it again.
- `words` tie each word to the strokes that wrote it (`s`, empty when the line's gaps didn't match its words), and `alts` lists other readings when recognition wasn't sure (for Convert to text).
- **Never holds a page with a password.** A page or notebook that gets one loses its entries at once, and nothing is written for it while it has one.

## Export and import
A `.board` file is the package zipped, with `notebook.json` at the top of the zip (a zip holding one `<name>.board/` folder is read too). Pictures and PDFs are stored without compressing them again.

- **Export** writes what is on disk, after the open notebook is saved. Locked pages stay sealed (`.json.enc`), with their `lock.json` entries, so the password still protects them. Exporting some pages writes a `notebook.json` listing only those pages, only their entries in `lock.json`, and only the files their clear pages use (plus every sealed file, if a locked page goes along, since which pages use them can't be read without the password). Without images, `assets/` is left out and pictures show as empty boxes.
- **Import** makes a new notebook: a new `id`, the folder picked in Import into, `pinned` false, `trashedAt` null, `updatedAt` now. Everything else in `notebook.json` and every page and item, ids included, comes in as it was. Only `notebook.json`, `lock.json`, `pages/<pageId>.json(.enc)` for page ids listed in `notebook.json` (letters, digits, `_` and `-`), `index/recognition.json`, and `assets/<name>` with a plain file name are read: nothing else in the zip is written anywhere. A page whose file is damaged comes in empty. Fingerprint unlock has to be turned on again for the copy.
- `index/recognition.json` goes along when "Include recognized handwriting text" is on (the default), with only the exported clear pages. Import keeps it for clear pages only, and not at all for a notebook with a password, so search works straight away.

## Outside the packages
The app's data folder also holds `settings.json`, `library.json` (folders: `{"version": 1, "folders": [{"path": ["School", "Physics"], "color": "#2B5A8C"}]}`), `templates/<id>.json` (My templates: `format: "endless.template"`, `name`, `paper`, `template`, `items`) and `index.sqlite` (the library index, a cache rebuilt from the packages).

## Rules
- Unknown item types and fields must be kept on load and written back on save, so newer files survive older apps. A known type whose fields can't be read (a missing `w`, a bad color) is kept as it is too.
- Stroke points are stored as flat numbers rounded to 0.1 px. A future binary encoding can come in v2.
- Sync merges at item level by `id`, so two devices never overwrite each other's strokes.
