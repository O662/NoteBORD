# Progress

Status of each phase in `docs/SPEC.md`. Updated as work lands.

## Phase 0: Foundation — done (Paper theme only)

| Item | Status | Where |
|---|---|---|
| Flutter project (Android + Windows; iOS, Linux, macOS and web can be added with `flutter create --platforms=… .`) | Done | repo root |
| Theme from `design/tokens.json`: Paper light and dark | Done | `tool/gen_tokens.dart` → `lib/theme/tokens.g.dart`, `lib/theme/app_theme.dart` |
| Figtree, Newsreader and Caveat bundled, with OFL licenses registered | Done | `assets/fonts/`, `lib/main.dart` |
| Modes: Light, Dark, Match tablet | Done, switched from ⋯ → Settings (a stand-in until the Settings screen exists) | `lib/ui/canvas/top_bar.dart` (`showQuickSettings`) |
| Other themes (Midnight, Sage, Blush, Graphite, High contrast, Harbor) and accent colors | Swatches are generated; full palettes come with the Themes screen | `themeSwatches`, `accents` in `tokens.g.dart` |
| Routing | `go_router`: Start `/`, Library `/library` (a folder is `?f=School&f=Physics`), Trash `/trash`, a notebook `/notebook/:id?page=`, Split view `/split`. Calendar, Flashcards, Remember and Settings are added as they're built | `lib/app.dart`, `lib/ui/routes.dart` |
| Local storage and autosave | Done. Each notebook is a `.board` folder in the app's documents directory; see below | `lib/board/store.dart` |
| Save status in the title pill | `Saving… / Saved / Couldn’t save · retrying` | `TitlePill` |
| drift (SQLite) index | Done in Phase 2 (see below) | `lib/library/index_db.dart` |

**Token additions.** `design/tokens.json` had only 7 colors per theme for dark mode, so I added `colors.baseDark` (the full Paper dark palette taken from `design/source/CanvasDark.dc.html`), `colors.inkDisplayDark` (how ink colors brighten in dark mode) and `onAccent` / `shadow`. After editing tokens, run `dart run tool/gen_tokens.dart`; `test/tokens_sync_test.dart` fails if you forget.

## Phase 1: Ink and the endless page — built, needs a full S Pen check on the tablet

Checked on 2026-09-28 on a Galaxy Tab S9 FE (SM-X510, Android 16, 1317×823 dp landscape):
- the app launches in dark mode ("Match tablet")
- S Pen strokes draw
- pages were written to storage about 0.6 s after the last stroke
- the title pill goes from "Saving…" to "Saved"

Not yet checked there: how the pen feels, latency, and palm rejection.

| Item | Status | Notes |
|---|---|---|
| Canvas chrome matching `Canvas.png` | Done | Title pill, tool pill, Share/Export/⋯, left rail, pages rail, map, zoom pill, hint pill, More colors tray, pen popover. Icons use the exact SVG paths from `Canvas.dc.html` |
| Buttons not wired yet | "… is coming soon" snackbar | Select, Lasso, Shapes, Text, rail menu items, Search, Share, ⋯ items except Settings, Back to library, Custom color |
| Endless page, dot background | Done | Lines, grid and blank papers are implemented; no UI to choose them until Templates |
| Stylus drawing with pressure | Done | Variable-width outline from S Pen pressure (`lib/canvas/stroke_geometry.dart`) |
| Pen types | Ballpoint, Fountain (more pressure range), Pencil (softer, 85% opacity) | |
| Marker (highlighter) | Done | 4× width, 40% opacity, no pressure, never darkens where it overlaps itself |
| Eraser | Done, whole-stroke | One drag = one undo step |
| S Pen side button held = temporary eraser | Done | Also the S Pen's eraser end (`invertedStylus`) if present. Not yet configurable (Settings screen) |
| 3 quick colors + More colors tray (up to 10) | Done | + adds the next unused color, edit mode removes colors, n/10 counter |
| Pen popover | Done | Pen type, 9 colors (+ custom: coming soon), 5 thicknesses, preview, 4 toggles, S Pen tip. Pen and marker keep their own color and size |
| Popover toggles "snap shapes", "scribble to erase", "flick for arrows" | Saved, not active yet | Those features are Phase 3 |
| Undo / redo | Done, per page, 200 steps | Ctrl+Z / Ctrl+Y / Ctrl+Shift+Z on a keyboard |
| Two-finger pan and pinch zoom | Done | One finger pans too. Mouse wheel pans, Ctrl+wheel zooms, trackpad pinch works |
| Zoom pill | Done | −, % (tap = 100%), +, whole board (fit to ink), full screen |
| Palm rejection | Done | Touches are ignored while the S Pen is down or seen within 600 ms (hovering counts), and a pen touch cancels any finger gesture in progress |
| Pages rail | Done | Live thumbnails, current page, locked indicator, add page, collapse |
| Map | Done | Minimap of the page and your view; tap or drag to move; collapse |
| Autosave in ≤ 1 s + crash safety | Done | Written ~0.4 s after the first unsaved change, flushed when the app is backgrounded. Files are written to a temp file and renamed, so a crash mid-write keeps the previous version |
| Hover ring under the S Pen | Done | Shows pen size and color, or the eraser size |
| Draw with finger | Off by default; toggle in ⋯ → Settings | For trying the app without a stylus |

### Not done yet / known limits
- **Ink latency has not been measured on the device.** Rendering is split so only the active stroke repaints while you write. If writing feels laggy on the tablet (target: under about 25 ms), the next step is Android front-buffered rendering (androidx.ink / `GLFrontBufferedRenderer`) through a platform view, as CLAUDE.md suggests.
- Committed ink is cached as a vector picture of the strokes near the view. Very large pages may need raster tiles later; measure first.
- Tool button sizes follow the design markup, which has a few targets under 44×44 (quick color swatches are 36×44, tray swatches 40×44, zoom pill buttons 40×40 or 34×40 with the map button, the map toggle 44×36).

## Update 01: canvas chrome cleanup — done (docs/UPDATE_01.md)

| Item | Status | Where |
|---|---|---|
| Compact left rail: Insert, Study & math, Writing help, Ruler/laser/view, divider, Search | Done, with the corner tick on group buttons | `lib/ui/canvas/left_rail.dart` (`railGroups`) |
| Rail menus: hover (S Pen hover or mouse) previews, tap pins ("Pinned" + ×) | Done. Pinned menus close on a tap outside (which doesn't draw), a re-tap, the ×, Esc, or picking an item | `LeftRail`, `CanvasScreen` |
| Menu items | "Coming soon" for now. Tool items (sticky, frame, image, ruler, laser) will switch the tool once those tools exist (Phase 3) | |
| Top right: dark Share + ⋯ | Done; Export button and top-bar spell check removed | `ActionsPill` |
| ⋯ menu: Export, Import, Print, Password protect, Page & paper, Version history, Settings | Done. Settings opens a small stand-in (Light/Dark/Match tablet, Draw with finger); the rest are "coming soon" | `MoreMenu`, `showQuickSettings` |
| Share dialog "Export a copy" row | Waits for the Share dialog (Phase 9) | |
| Map card above the zoom pill, both 236 dp, right-aligned | Done | `MapPanel`, `ZoomPill` |
| Zoom pill: −, %, +, show map (when hidden), whole board, full screen | Done. With the map button the pill's buttons narrow to 34–36 dp to fit 236, as in the design. Whole board fits the page's ink until the Board screen exists | |
| Full screen hides every menu except the zoom pill | Done; "Show map" in full screen brings the menus back with the map | |
| Tokens | Added `menuTile`, `clayDeep`, `greenDeep` (light and dark) for the menu icon tiles | `design/tokens.json` |
| No tooltips on chrome buttons | Removed after tablet testing: S Pen hover popped them up over the page. Labels remain for accessibility | `ChromeButton` |
| Zoom pill at large font sizes | Buttons share the 236 dp in proportion and the % shrinks to fit; tested at font scale 1.1 (the tablet), 1.3 and 1.5. The title pill caps its text scale at 1.3 so two lines fit the top bar | `ZoomPill`, `TitlePill` |
| Goldens | default (light/dark), pen popover, rail pinned, rail hover (Insert), ⋯ menu, map hidden, full screen | `test/golden/` |

## Phase 2: Library and organisation — built, needs a check on the tablet

The app now opens on the Start page. Start → Library → a notebook → Canvas works, and so do the ways back: the title pill's back arrow returns to wherever the notebook was opened from.

| Item | Status | Where |
|---|---|---|
| Start page matching `Start.png` | Done. Date, "Welcome back, <name>" (name set in Settings), the five action cards, Continue writing (the notebook opened last, with its ink, page and folder, plus Open and Split view), Pinned, Recent, See all notebooks | `lib/ui/library/start_screen.dart` |
| Sidebar | Done. Search, Home, All notebooks (with its count), Calendar, Flashcards, Remember, Trash, folders, save status, Settings. On the Start page folders are a flat list; in the Library they're a tree with chevrons and a + | `lib/ui/library/sidebar.dart` |
| Library matching `Main.png` | Done. Breadcrumb (each part opens that folder), title, grid/list toggle, Import, New notebook, New note, subfolders with counts, New folder, sort (Last edited, Title, Date created), covers with the notebook's ink, "Locked" covers. View and sort are remembered | `lib/ui/library/library_screen.dart` |
| Nested folders | Done. Create, rename (notebooks and subfolders move along), recolor, delete (its notebooks go to the Trash). Long-press or right-click a folder | `LibraryNotifier`, `showFolderMenu` |
| Notebook actions | Long-press or right-click a card: Open, Open in split view, Rename, Move to folder, Color, Pin to Start, Move to Trash. Tapping the title in the canvas renames too | `showNotebookMenu` |
| Trash | Done. Restore, Delete forever, Empty trash; emptied automatically after 30 days | |
| "Waiting to sync" badge | Not shown until cloud sync exists (Phase 7) | |
| Templates matching `Templates.png` | Done. All 11 layouts from the design plus "Save as template"; categories All, Paper, Study, Planning, Boards, My templates; "Use for" a new page (after the current one) or a new notebook. Layouts are drawn under the ink and the page stays endless. Opened from Insert → Templates, New notebook and From a template. Long-press one of My templates to delete it | `lib/templates/templates.dart`, `lib/ui/templates/templates_dialog.dart` |
| Use a template for a Frame | "Coming soon": frames are a Phase 3 item | |
| Password protection matching `Lock.png` | Done for a page or the whole notebook: password, confirmation, hint, fingerprint or face unlock, the can't-recover warning. A locked page shows the frosted unlock card. Opening ⋯ → Password protect on a protected page offers "Lock now" and "Remove password" | `lib/board/lock.dart`, `lib/ui/lock/` |
| Encryption | AES-256-GCM per page, key from Argon2id (19 MiB, 2 passes, OWASP minimum) run on a background isolate. Only `pages/<id>.json.enc` is on disk while a page is locked; covers never show locked ink. Unlocked pages lock again when the notebook is closed | `LockCrypto`, `NotebookNotifier` |
| Fingerprint or face unlock | `local_auth` + `flutter_secure_storage`: the page's key (never the password) is kept in the Android Keystore and released after a biometric check. `MainActivity` is now a `FlutterFragmentActivity` with AppCompat launch themes, as `local_auth` requires | `lib/state/biometric.dart`, `android/` |
| Split view matching `Split.png` | Done. Two notes, or two pages of one note (Same note / Other note), swap, drag the divider to resize, page arrows per side, a notebook picker in each header, close either side. The pen writes only in the focused side: a pen tap on the other side moves the focus there first, and fingers pan and zoom either side | `lib/ui/split/split_screen.dart` |
| One notebook provider per notebook | `notebookProvider(id)` loads on demand and saves when closed; the page shown lives in a `Pane`, so two panes can show one notebook | `lib/state/notebook.dart`, `lib/canvas/pane.dart` |
| drift index | One row per notebook (title, folder, cover, dates, page count, pinned, trashed, locked, a small vector thumbnail, and where this tablet left off). Rebuilt from the `.board` files at startup when rows are missing or stale; the files stay the source of truth. Raw SQL for now: drift's code generator doesn't run on this Flutter SDK yet | `lib/library/index_db.dart`, `loadLibrary` |
| Tokens | Added `sideSelected`, `lineDashed`, `accentWash`, `switchOff`, `warningTint`, `onWarning`, `goldDeep`, `moss`, `paperLine`, `paperGrid`, `paperMargin`, `scrim`, `frost` (light and dark) and the six `covers` colors | `design/tokens.json` |

### Not done yet / known limits
- **Not yet tried on the tablet**, including the fingerprint prompt. It has been checked in tests, a debug APK build, and a Windows build that starts on the Start page.
- Search, Import, Scan, Calendar, Flashcards, Remember and cloud sync are "coming soon" (later phases). Flashcards and Remember show no counts until those features exist.
- Locked content is dropped from memory when you leave the notebook, not when the app goes to the background.
- A page locked with its own password inside a locked notebook keeps its own password; unlocking the notebook doesn't open it.
- Library covers show the page this tablet last had open (or else the first page with ink). The small Recent cards show the notebook's color only, as in the design.
- New notebooks are called "Untitled note" / "Untitled notebook"; tap the title in the canvas to rename.

## Storage layout

```
<app documents>/Endless/
├── settings.json                  # tools, colors, theme mode, your name, library view and sort
├── library.json                   # folders and their colors, in the order they were made
├── index.sqlite                   # the library index (a cache; rebuilt from the .board files)
├── templates/<templateId>.json    # My templates
└── notebooks/<notebookId>.board/  # the .board package, unzipped (docs/BOARD_FORMAT.md)
    ├── notebook.json
    ├── lock.json                  # only when a page or the notebook has a password
    └── pages/<pageId>.json        # or <pageId>.json.enc while locked
```

## Tests

`flutter test` runs:
- `test/board`: `.board` round trips, unknown item types and fields preserved, rounding, atomic file writes, sealed pages and lock.json, library.json, templates; real Argon2id + AES-GCM (with cheap test parameters), wrong passwords, page and notebook locks, fingerprint unlock, removing a lock.
- `test/canvas`: stroke geometry and pressure, eraser hit testing, spatial index, pan/zoom math.
- `test/library`: the drift index (round trip, refresh from files, deleted notebooks, 30-day Trash), cover thumbnails, notebook and folder operations, Continue writing / Pinned / Recent, templates, date wording.
- `test/state`: loading, undo/redo per page, eraser undo, adding pages with a template, autosave timing, a library rename while the notebook is open, settings.
- `test/ui`: the Canvas screen (as before); Start and Library (labels, Start → Library → notebook → back, New note, grid/list, sort, new folder, rename, pin, trash, restore, delete forever, folder rename and delete); Templates (categories, new page, save as template, new notebook from Start); Password protect (mismatch, lock, wrong password, fingerprint, remove, a locked notebook); Split view (focus, the pen only writing in the focused side, undo, page arrows, Same/Other note, swap, closing a side, opening from Start).
- `test/golden`: Canvas at 1280×800 in 8 states, plus Start, Library (grid and list), Templates, Password protect, a locked notebook and Split view, using the design's sample library (`test/sample_library.dart`). Goldens were rendered on Windows; regenerate with `flutter test --update-goldens test/golden` after an intended visual change.
- `test/tokens_sync_test.dart`: generated tokens match `design/tokens.json`.

## Next
- Try Phases 1 and 2 on the tablet: ink feel, latency and palm rejection; the library; locking with a fingerprint; Split view with the S Pen.
- Then Phase 3: shapes, text, stickies, frames (which also turns on "Use for: Frame" in Templates), selection and the rest of the canvas tools.
