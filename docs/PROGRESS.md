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
| Buttons not wired yet | "… is coming soon" snackbar | Search, Share, ⋯ items except Settings and Password protect, Custom color, and the Study & math and Writing help menus. (Select and Lasso work since Phase 3a; Shapes, Text and the Insert menu since Phase 3b.) |
| Endless page, dot background | Done | Lines, grid and blank papers are implemented; no UI to choose them until Templates |
| Stylus drawing with pressure | Done | Variable-width outline from S Pen pressure (`lib/canvas/stroke_geometry.dart`) |
| Pen types | Ballpoint, Fountain (more pressure range), Pencil (softer, 85% opacity) | |
| Marker (highlighter) | Done | 4× width, 40% opacity, no pressure, never darkens where it overlaps itself |
| Eraser | Done, whole-stroke | One drag = one undo step |
| S Pen side button held = temporary eraser | Done | Also the S Pen's eraser end (`invertedStylus`) if present. Not yet configurable (Settings screen) |
| 3 quick colors + More colors tray (up to 10) | Done | + adds the next unused color, edit mode removes colors, n/10 counter |
| Pen popover | Done | Pen type, 9 colors (+ custom: coming soon), 5 thicknesses, preview, 4 toggles, S Pen tip. Pen and marker keep their own color and size |
| Popover toggles "snap shapes", "scribble to erase", "flick for arrows" | Active since Phase 3a | Each turns its gesture on or off |
| Undo / redo | Done, per page, 200 steps | Ctrl+Z / Ctrl+Y / Ctrl+Shift+Z on a keyboard |
| Two-finger pan and pinch zoom | Done | One finger pans too. Mouse wheel pans, Ctrl+wheel zooms, trackpad pinch works |
| Zoom pill | Done | −, % (tap = 100%), +, whole board (Phase 3b), full screen |
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
| Menu items | Ruler, Laser pointer, Templates and Split view work; "Need to remember" and "Convert to text" start a lasso (Phase 3a); the whole Insert menu is wired (Phase 3b). The rest are "coming soon" | |
| Top right: dark Share + ⋯ | Done; Export button and top-bar spell check removed | `ActionsPill` |
| ⋯ menu: Export, Import, Print, Password protect, Page & paper, Version history, Settings | Done. Settings opens a small stand-in (Light/Dark/Match tablet, Draw with finger); the rest are "coming soon" | `MoreMenu`, `showQuickSettings` |
| Share dialog "Export a copy" row | Waits for the Share dialog (Phase 9) | |
| Map card above the zoom pill, both 236 dp, right-aligned | Done | `MapPanel`, `ZoomPill` |
| Zoom pill: −, %, +, show map (when hidden), whole board, full screen | Done. With the map button the pill's buttons narrow to 34–36 dp to fit 236, as in the design. Whole board is the Phase 3b view | |
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
| Use a template for a Frame | Done in Phase 3b: a sheet of that paper, or of that layout, on the page you're on | `insertTemplateFrame` |
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

## Phase 3a: pen gestures and canvas tools — built, checked on the tablet (2026-09-29), with fixes after

The first half of Phase 3: selection and the pen gestures. Shapes, text boxes, stickies, frames and the Insert menu are Phase 3b.

**Tablet check, 2026-09-29.** Hold to straighten, select/lasso (pen, one and two fingers, corners, straighten lines), ruler, laser, zoomed use and palm rejection all worked. Fixed afterwards:
- Flick arrows: only 4 of 20 worked, some facing the wrong way. The tip is now found as the furthest point along the line (real S Pen tips are rounded, which failed the old sharp-corner test and the smoothness check right before the tip), hooks may curve and take up to 500 ms, and a start hook must angle away from the line (15–50°) and be at least 12 px, so a landing backswing no longer adds a head at the wrong end. On 500 simulated pen flicks: 97% become arrows; 0 plain lines (with or without a backswing) and 0 of 500 zig-zags do.
- Scribble to erase reacts twice as fast (Light 2, Normal 3, Firm 4 back-and-forths).
- A finger can now drag the rotate knob and corner handles.
- Ruler: pinch along it to lengthen or shorten it (past a 12% dead zone, so turning it doesn't resize it), cm / mm / inch ticks and numbers, the length of a line drawn along it in the chip, and a tap on the chip opens presets, a number pad (to 3 decimals, ±) and the unit.

| Item | Status | Where |
|---|---|---|
| Undo for item edits | Done. `ReplaceStep` joins insert and remove, so move, resize, rotate, recolor and straighten are one undo step each and keep the item's id and place in the z-order. Straightening and arrows are two steps: the ink as drawn, then the change, so Undo turns a shape back into your ink | `lib/state/notebook.dart` (`replaceItems`, `removeItems`, `insertItems`) |
| Gesture recognizers | Pure functions with unit tests. Thresholds are in screen px, so they behave the same at any zoom | `lib/canvas/gestures.dart` |
| Hold to straighten (`Tools.png`) | Done. The pen held still (within 4 px) for 150 ms shows a ring, a dashed preview and "Hold to straighten…" while the ink fades; at 500 ms it snaps to a line, circle, oval, rectangle or triangle. Lines snap to 0°, 45° and 90° within 3°; rectangles square up to the page within 6°. After the snap a line's end follows the pen, with its end circles, a dashed level line and the angle. Lifting shows "Line straightened · Undo". Stored as `straightened` on the stroke | `fitShape`, `InkCanvas` |
| Flick back for an arrow (`Arrows.png`) | Done for either end or both, on straight lines and curves. The tip is where the pen got furthest along the line; the hook must be 7–50 screen px, at most half the smooth run of line before it, quick (≤ 500 ms), and fold back within 75° (a start hook: 15–50°, at least 12 px), so zig-zags, check marks, backswings and long strokes back stay ink. Debug builds log why a hook didn't count (`flutter logs`, "No arrow: …"). The hook is trimmed and the stroke gets `arrow: {start, end, style}`. Heads are drawn from the stroke's color and width: Open, Filled or Like my ink (a tapered, slightly bowed chevron in the same pen). "Made an arrow · Undo" | `detectFlicks`, `arrowHeadPaths` |
| Connectors that snap to shapes | Not yet. Shape items exist since Phase 3b; arrows don't attach to them | |
| Scribble to erase (`Scribble.png`) | Done for the pen and marker. Counts sharp back-and-forth turns (Light 2, Normal 3, Firm 4 plus a denser path) and only acts when there is ink under it: a stroke goes only if the scribble touches it and at least half of it lies in the scribbled area, so long lines it clips and shading on empty paper are safe. While scribbling, what will go turns faded red with "Lift the pen to erase N strokes"; the scribble itself is never kept. "Erased N strokes · Undo" (the design's "word" needs handwriting recognition, Phase 5) | `looksLikeScribble`, `scribbleTargets` |
| Select and Lasso (`Convert.png`, `RememberMark.png`) | Done for ink. Select: tap a stroke or drag a box. Lasso: circle strokes (half their points inside). The dashed outline has corner handles (uniform resize; the pen width scales too) and a rotate knob (settles on 0/90/180/270° within 4°). Drag inside with the pen, or one finger, to move; the handles work with the pen or a finger; two fingers on the selection pinch and turn it. Page and tool changes, Esc and an empty tap clear it | `lib/canvas/selection.dart`, `InkCanvas` |
| Selection toolbar | Done, 12 px above the selection (below it when the top chrome is in the way). Leads with **Convert to text** (Copy · Color · Straighten lines · Delete), or with **Remember** (To text · Flashcard · Copy · Delete) when started from the rail's "Need to remember". Copy duplicates 24 px down-right and selects the copy; Color offers the 9 pen colors; Straighten lines fits each selected stroke. Convert to text, Remember and Flashcard are "coming soon" (Phases 5 and 7) | `lib/ui/canvas/selection_toolbar.dart` |
| Ruler (`Tools.png`) | Done. Rail → Ruler, 620 × 72, level across the lower middle; pick it again to put it away. One finger drags it, two fingers move and turn it (whole degrees, settling on multiples of 45° within 2°) and, spread along it past a 12% dead zone, make it 240–2400 px long. Dragging either end (finger or pen, the grips 48 px in from each end) swings and stretches it about the other end, with the same whole-degree and 45° settling; a second finger joining turns that into a normal two-finger move. Ticks in cm, mm or inches (an inch is 160 page px, Android's dp, so at 100% it matches a real ruler; they follow the zoom). Its chip shows the angle (counter-clockwise positive, −180° to 180°) and, while you draw along it, the line's length. Tapping the chip (pen or finger) opens presets (0–180°), a number pad (to 3 decimals, ±) and the unit (`lib/ui/canvas/ruler_menu.dart`). A pen stroke that starts on it or within 28 px of an edge is laid along the nearer edge, just outside it. It lives in screen space, so it stays put while the page pans | `lib/canvas/ruler.dart` |
| Laser pointer (`Tools.png`) | Done. Rail → Laser pointer makes it the tool; red, green or blue under the tool pill. The trail lives in page space, each point fades over 1 s, and nothing touches the notebook (no undo step, no save). The app never reopens on the laser | `lib/canvas/laser.dart` |
| Settings | Arrowhead (Open / Filled / Like my ink) and scribble sensitivity (Light / Normal / Firm), plus the two switches, in the stand-in Settings dialog, styled like the "Settings › Pen & S Pen" panels until the Settings screen exists | `lib/ui/canvas/pen_settings.dart` |
| Status and Undo toasts | Shown at the bottom center, in place of the tool hint. They last 4 s, and the next edit dismisses them, so their Undo always means that gesture. Split view shows them per pane | `lib/ui/canvas/gesture_status.dart` |
| Tokens | Added `laserRed`, `laserGreen`, `laserBlue`, `scribbleMark` and `onStar` (light and dark) | `design/tokens.json` |

### Not done yet / known limits
- Tapping a different stroke inside an existing selection's box moves the selection instead of selecting that stroke; tap outside first.
- Rotating bakes the rotation into the points (`rotation` stays 0 for strokes).
- The selection toolbar buttons are 40 px tall, as in the design (under the 44 dp target).

## Phase 3b: things on the page, the Insert menu and the whole board — built, not yet tried on the tablet

The rest of Phase 3, as scoped for this round: text boxes, sticky notes and stacks, paper frames, images, the full Insert menu and the whole-board view, plus basic shapes. Everything is an item in the `.board` page (docs/BOARD_FORMAT.md) and every change is one undo step.

| Item | Status | Where |
|---|---|---|
| Item types | `text`, `sticky`, `frame`, `image`, `shape`. Each is a box with a rotation (degrees, about its center), so they move, turn, scale, copy and delete alike. Anything this version can't read is still kept as it was | `lib/board/model.dart` (`BoxItem`), `lib/board/codec.dart` |
| Drawing and hit testing | In the page's cached picture with the ink, in z-order; the map and page thumbnails show them too | `lib/canvas/items.dart` |
| One undo step | `edit()` replaces, removes and adds in one command (fan out, stack); `insertItems(at:)` puts paper under the ink; `reorder()` is To front / To back; `eraseInk()` rubs ink off a sticky inside an eraser drag | `lib/state/notebook.dart` |
| Text boxes | The Text tool (tool pill, or Insert → Text box): tap the page to type, tap a box or a sticky note to edit it. A bar over the field picks the font (plain, serif, handwriting), steps the size (14–64) and has Done. A new box hugs its text up to 480 px, then wraps; stretched by an edge, it wraps at that width. Tapping anywhere else, Done, Esc or another tool puts it on the page; an emptied box is removed. It takes the pen's color. While typing, Ctrl+Z undoes the typing, not the page | `lib/ui/canvas/text_editor.dart`, `InkCanvas` (`_beginEdit`, `_commitEdit`) |
| Sticky notes (`Board.png`) | Insert → Sticky note, then tap (pen or finger) to drop one: 242 × 220, yellow, tilted 2° like the design. The tool goes back to the pen, and ink that starts on a note is written on the note: it is stored inside it and moves, turns and scales with it. Hold to straighten, flick arrows, scribble to erase and the eraser all work on a note's ink. Typed text too (Text tool, or Select → Edit text). Paper colors: yellow, pink, peach, green | `StickyItem`, `_putStroke`, `_swapStroke` |
| Sticky stacks | Insert → Sticky stack drops three blank notes (pink, peach, green). The fan shows up to two notes underneath and a badge with the count ("5 notes"). Select it for **Fan out** (separate notes side by side) and **Next note** (the top one goes to the bottom); select several notes for **Stack**. Tapping the badge with Select fans out. The notes under the top one are stored with their ink (`stack.notes`) | `_fanOut`, `_nextNote`, `_stackSelected` |
| Paper frames (`Board.png`) | Insert → Paper frame, then tap: a lined A4 sheet (560 × 792, ruled every 40 px with a margin), named "Frame · Lined A4" above it, placed **under** what's already written. Writing on it is ordinary page ink; what's written on a frame goes with it when it's moved, resized, turned, copied or deleted. Select → Rename names it. Other papers exist in the format (grid, dots, blank) and come from Templates | `FrameItem`, `_riders` |
| Templates → Frame | "Use for: Frame" now works: paper templates make a sheet of that paper; layouts (Cornell, planner…) are drawn on the sheet, scaled to its width. My templates bring their paper and layout, not their ink | `insertTemplateFrame` |
| Images | Insert → Image (or the menu's "Image or photo", "This tablet", "Camera"): from photos and files, or the camera where the device has one (`image_picker` 1.2.3). Photos over 2400 px are scaled down. The file is stored once in the package's `assets/` under its SHA-256; the picture lands in the middle of the view (at most 480 × 360), selected. Corner handles resize it in proportion. What's written on a picture moves with it | `NotebookNotifier.addImage`, `lib/state/assets.dart`, `lib/state/photos.dart` |
| Images on locked pages | Sealed with the page's key (AES-256-GCM) as `assets/<name>.enc`. Locking a page or notebook seals its images and deletes the clear copies, including pictures deleted from the page earlier; removing the password writes them back. Pictures of a locked page are dropped from memory with it | `_rewriteAssets`, `_dropUnusedClearAssets` |
| Shapes (basic) | The tool pill's Shapes button, or Insert → Shape: rectangle, oval, triangle, line or arrow, picked in a strip under the tool pill. Drag to draw (a tap drops one at its usual size); it takes the pen's color and thickness, and is left selected. No fill, and no connectors that attach | `ShapeItem`, `ShapeKinds` |
| Selecting objects | Select and Lasso take everything: a tap picks the topmost thing, a box or lasso what's mostly inside. A shape without a fill is picked by its outline, so what's inside stays reachable. One box on its own gets an outline that follows its tilt, square handles on its edges to stretch it (text and lines only sideways; pictures keep their shape) and a rotate knob that settles it upright | `SelectionFrame`, `stretchBox` |
| Toolbar for objects | With no ink selected: Edit text / Fan out · Next note / Stack / Rename as fits, then Copy · Color · To front · To back · Delete. Color offers paper colors for sticky notes and ink colors for text and shapes. With ink in the selection it is the Phase 3a toolbar | `SelectionToolbar(objectActions:)` |
| Insert menu (`Insert.png`) | Done, from the rail's "Everything else": the four groups and their 26 tiles, "Pick files from", the footer and Browse templates, at the design's sizes. Search works (by name, or the start of another word: "lined" finds Paper frame). Sticky note, Sticky stack, Text box, Paper frame, Shape, Image or photo, This tablet and Camera do their thing | `lib/ui/canvas/insert_menu.dart`, `insert_actions.dart` |
| "Coming soon" card | Every tile outside this round opens a card with its icon, "Coming soon" and what it will do, and the menu stays open: Video, Audio, PDF, Word, PowerPoint, Excel, Math, Graph, Table, Diagram, Timeline, Kanban, Website, the seven live widgets, Google Drive, OneDrive and Scan. "Record audio" in the rail opens the same card | `lib/ui/canvas/coming_soon.dart` |
| Whole board (`Board.png`) | The zoom pill's board button glides out to fit everything on the page, hides every menu except the zoom pill, and shows a hint. Two fingers still pan and zoom. A tap (pen or finger) glides back in, centered there, at the zoom you had; the button or Esc goes back to exactly where you were. Nothing can be written there | `CanvasScreen._toggleBoard`, `InkCanvas(onBoardTap:)` |
| Status messages | "Added a sticky note to the page · Undo" and the like, in the same place as the pen gestures' messages | `Pane.toast` |
| Tokens | Added `cardLine`, `plumDeep`, `stickyDeep` (light and dark) and the `stickies` paper colors | `design/tokens.json` |

**Also fixed:** closing a notebook within 0.4 s of the last change could lose that change in debug builds (the save on close read the provider's state while it was being disposed, which Riverpod refuses). The last save no longer needs the state, and a test covers it.

### Not done yet / known limits
- **Not tried on the tablet yet.** In particular: the photo picker and camera, the keyboard over a text box near the bottom of the screen, and how finger taps for dropping things feel next to panning.
- **Left out of this round, still in SPEC Phase 3:** Kanban, timeline, diagram, website and Word / PowerPoint / Excel previews (they are on `Board.png` and open the "coming soon" card), and connectors that attach to shapes.
- Shapes have no fill and no corner radius, and a line can't be dragged by its ends (rotate it and stretch it instead).
- A text box has one font, size and color for all of its text.
- The eraser only takes ink. Objects are deleted with Select → Delete.
- A scribble over a sticky note's ink shows it in red but can't hide it first, as it does for page ink.
- Corner handles resize about the opposite corner of the outline, which sits 8 px outside the object.
- Library covers and the Start page still show a page's ink only, not its sticky notes or pictures.
- Image files that nothing uses any more stay in `assets/` (they are only cleaned up when a page is locked). `crop` is kept in the file but there is no cropping yet.
- The camera isn't offered on Windows (the plugin has none there).
- Frame names are drawn on the page, so they get small on the whole board.
- Split view has no strip for picking the shape; it draws the last one picked.

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
    ├── pages/<pageId>.json        # or <pageId>.json.enc while locked
    └── assets/<sha256>.<ext>      # images; <name>.enc on a locked page
```

## Tests

`flutter test` runs:
- `test/board`: `.board` round trips, unknown item types and fields preserved, rounding, atomic file writes, sealed pages and lock.json, library.json, templates; real Argon2id + AES-GCM (with cheap test parameters), wrong passwords, page and notebook locks, fingerprint unlock, removing a lock. Phase 3b (`items_test.dart`): text, sticky, stack, frame, image and shape round trips, unreadable items kept as they were, box geometry under rotation, scaling and copying what's inside a note, stretching an edge, hit testing, image file names, and the assets folder.
- `test/canvas`: stroke geometry and pressure, eraser hit testing, spatial index, pan/zoom math; the gesture recognizers (shapes, flicks, scribbles and sensitivity, lasso), selection transforms, and arrow/straightened round trips.
- `test/library`: the drift index (round trip, refresh from files, deleted notebooks, 30-day Trash), cover thumbnails, notebook and folder operations, Continue writing / Pinned / Recent, templates, date wording.
- `test/state`: loading, undo/redo per page, replace/remove/insert as single steps, eraser undo, adding pages with a template, autosave timing, saving when a notebook is closed right after a change, a library rename while the notebook is open, settings. Phase 3b (`items_state_test.dart`): combined edits and reordering as one undo step, erasing ink on a note, objects on disk within a second, adding an image (and refusing a file that isn't one), templates leaving pictures out, and images sealed, reopened and unsealed with page and notebook passwords.
- `test/ui`: the Canvas screen (as before); pen gestures end to end with S Pen and finger events (hold to straighten and its Undo, arrows, scribble and sensitivity, the popover toggles, lasso and Select, move/resize/rotate/pinch, copy/recolor/straighten/delete, the Remember toolbar, the ruler, the laser); Start and Library (labels, Start → Library → notebook → back, New note, grid/list, sort, new folder, rename, pin, trash, restore, delete forever, folder rename and delete); Templates (categories, new page, save as template, new notebook from Start); Password protect (mismatch, lock, wrong password, fingerprint, remove, a locked notebook); Split view (focus, the pen only writing in the focused side, undo, page arrows, Same/Other note, swap, closing a side, opening from Start).
- `test/ui/objects_test.dart` (Phase 3b): dropping a sticky note with the pen and a finger, writing on it, hold to straighten and scribble on a note, the eraser on a note, stacks (fan out, next note, stack, the badge), text boxes (type, edit, restyle, clear, Esc, recolor, stretch), frames (under the ink, carrying it when moved, copied and deleted; from Templates), shapes (drag, stretch, rotate, tap), images (from the picker, with and without a camera, resizing, ink riding along), selecting objects and the lasso with ink, the Insert menu (every tile, search, every "coming soon" card, Browse templates), the whole board (in, tap, back, Esc, finger), and everything saved and loaded again.
- `test/golden`: Phase 3b in 10 images (`insert`, `insert_dark`, `insert_search`, `insert_coming_soon`, `board`, `board_dark`, `objects`, `objects_selected`, `text_editing`, `shapes`). Canvas at 1280×800 in 8 states; the pen gestures in 9 (`gestures_*.png`: lasso, remember, hold, straightened, scribble, arrows, ruler and laser, ruler menu, settings); plus Start, Library (grid and list), Templates, Password protect, a locked notebook and Split view, using the design's sample library (`test/sample_library.dart`). Goldens were rendered on Windows; regenerate with `flutter test --update-goldens test/golden` after an intended visual change.
- `test/tokens_sync_test.dart`: generated tokens match `design/tokens.json`.

## Next
- Try Phase 3b on the tablet: drop and write on sticky notes, type a text box with the on-screen keyboard, add a photo from the gallery and the camera, and the whole board. (Dragging the ruler's ends from Phase 3a is still to try as well.)
- Decide whether the rest of SPEC Phase 3 (Kanban, timeline, diagram, website and Office previews, connectors) comes before Phase 4, import and export.
- Then Phase 4: export to PDF and `.board`, import PDF, images and `.board` files.
