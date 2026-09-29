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
| Routing | `go_router` with the Canvas route. Start, Library, Calendar, Flashcards, Remember and Settings are added as they're built | `lib/app.dart` |
| Local storage and autosave | Done. Each notebook is a `.board` folder in the app's documents directory; see below | `lib/board/store.dart` |
| Save status in the title pill | `Saving… / Saved / Couldn’t save · retrying` | `TitlePill` |
| drift (SQLite) index | Deferred to Phase 2, when the Library needs a notebook index and search. Phase 1 has one notebook, and the `.board` folders are the source of truth | |

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
- The notebook is created automatically ("Untitled notebook"). Renaming and multiple notebooks arrive with the Start page and Library in Phase 2.
- Locked pages show the lock in the rail, but locking itself is Phase 2.
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

## Storage layout

```
<app documents>/Endless/
├── settings.json                  # tools, colors, tray, theme mode, last notebook
└── notebooks/<notebookId>.board/  # the .board package, unzipped (docs/BOARD_FORMAT.md)
    ├── notebook.json
    └── pages/<pageId>.json
```

## Tests

`flutter test` runs:
- `test/board`: `.board` round trips, unknown item types and fields preserved, rounding, atomic file writes.
- `test/canvas`: stroke geometry and pressure, eraser hit testing, spatial index, pan/zoom math.
- `test/state`: first run, undo/redo, eraser undo, autosave timing, settings.
- `test/ui`: the Canvas screen (every label, stylus drawing, finger pan/zoom, palm rejection, side-button erase, popover, tray limits, coming soon, pages, zoom, mouse and finger drawing, dark mode).
- `test/golden`: Canvas at 1280×800 in 8 states (see Update 01). Goldens were rendered on Windows; regenerate with `flutter test --update-goldens test/golden` after an intended visual change.
- `test/tokens_sync_test.dart`: generated tokens match `design/tokens.json`.

## Next
- Try Phase 1 on the tablet with the S Pen: how the ink feels, latency, and palm rejection.
- Then Phase 2: Start page, Library, Templates, Lock, Split view, and the drift index.
