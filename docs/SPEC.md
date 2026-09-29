# Endless: feature spec (tablet)

Each feature names the screen that shows it (`design/screens/<Name>.png`, with source in `design/source/<Name>.dc.html`). Phases are the build order.

---

## Phase 0: Foundation
- Flutter project for Android tablet landscape, set up so phone, desktop and web can be added later.
- A theme system built from `design/tokens.json`: Paper (default), Midnight, Sage, Blush, Graphite, High contrast and Harbor, each with light and dark palettes. There are 8 accent colors. Modes are Light, Dark and Match tablet. **[Themes]**
- Routing between Start, Library, Canvas, Calendar/Planner, Flashcards, Remember and Settings.
- Local database, auto-save, and a save-status indicator in the title pill.

## Phase 1: Ink and the endless page
- **Endless page** that grows in every direction, with a dot background by default (lines, grid or blank optional). **[Canvas]**
- **Pen input:** S Pen pressure changes stroke width. The side button, held, acts as a temporary eraser, and this is configurable.
- **Tools** in the center pill: undo, redo, select, lasso, pen, marker (highlighter), eraser, shapes, text, 3 quick colors, "More colors", and a color/thickness dot. **[Canvas]**
  - Tapping the active pen opens the pen popover with color, thickness slider, pressure on/off, snap shapes, scribble to erase, and flick for arrows. **[Canvas]**
- **More colors tray:** a slim row under the center pill for up to 10 extra colors, with a "+" add button, an "n/10" counter and edit. It must stay small because it sits on writing space. **[Canvas]**
- **Zoom** pill in the bottom-right corner: −, %, +, a "show map" button when the map is hidden, whole board, and **full screen** (hides every menu except this pill). Pinch zoom and two-finger pan also work. **[Canvas, Canvas-fullscreen]**
- **Pages rail** on the right: thumbnails, current page, locked indicator and add page. It can collapse. **[Canvas]**
- **Map**: a minimap of the endless page. It sits directly above the zoom pill, right-aligned and the same width (236 dp). It can collapse, and the zoom pill then gets a "show map" button. **[Canvas, Canvas-map-hidden]**
- **Left rail** (floating, compact): 4 group buttons and Search. Each group button has a small corner tick to show it opens a menu. **[Canvas, Canvas-rail-hover-insert, Canvas-rail-pinned]**
  - **Insert** (blue +): Sticky note, Paper frame, Image, Record audio, Templates, Everything else (the full Insert menu).
  - **Study & math** (cap icon): Need to remember, Make flashcards, Math & graphs, Math tools.
  - **Writing help** ("abc✓" icon with a red squiggle): Spell check, Dictionary & thesaurus, Convert to text.
  - **Ruler, laser & view**: Ruler, Laser pointer, Split view.
  - **Search** opens directly, with no menu.
  - **How the menus open:**
    - **Hovering** (S Pen hover / Air view, or a mouse on desktop) opens the menu, and it closes when the pointer leaves the rail and the menu.
    - **Tapping** pins it open (it shows "Pinned" and an ×) until you tap outside, tap the same button again, or pick an item.
    - Tool items (sticky, frame, image, ruler, laser) switch the active tool and close the menu. Other items open their screen.
- **Top-right pill**: a dark **Share** button and **⋯**.
  - The ⋯ menu holds Export, Import, Print, Password protect, Page & paper, Version history and Settings. **[Canvas-more-menu]**
  - The Share dialog has an "Export a copy" row (PDF, Board file, Image). **[Share]**
  - There is no separate Export button on any screen.
- Autosave target: every change is on disk in 1 s or less, and crash recovery restores the last strokes.

## Phase 2: Library and organisation
- **Start page:** welcome, New note, New notebook, From a template, Import PDF or file, Scan paper notes, Continue writing card, Pinned, Recent. **[Start]**
- **Library:** sidebar with Home, All notebooks, Calendar, Flashcards (with due count), Remember (with count) and Trash, followed by nested folders. Notebook grid or list with covers, page counts, last edited, and locked and "waiting to sync" states. **[Main]**
- **Templates:** dot grid, lined, graph, Cornell, meeting notes, weekly planner, to-do, Kanban, mind map, storyboard, lab report, and "save this page as a template". A template can be used for a new page, a frame or a new notebook. **[Templates]**
- **Password protection** per page or per notebook: password, confirmation, optional hint, fingerprint/face unlock, and a warning that the password can't be recovered. **[Lock]**
- **Split view:** two notes side by side, or two pages of the same note, with a swap button. The pen writes in the focused side. **[Split]**

## Phase 3: Canvas tools and objects
- **Select and lasso:** move, resize, rotate, recolor, copy, delete, convert to text, remember, and make a flashcard. **[Convert, RememberMark]**
- **Shapes:** hold to straighten. Keep the pen still about 500 ms at the end of a stroke and it snaps to a line, circle, rectangle or triangle, with the angle shown. **[Tools]**
- **Flick back to make an arrow:** a short hook back at the end of a line becomes an arrowhead. It works on curves and on both ends, and connectors snap to shapes. Arrowhead styles are Open, Filled and "Like my ink". **[Arrows]**
- **Scribble to erase:** scribbling over ink erases only the strokes under the scribble. Sensitivity is Light, Normal or Firm. **[Scribble]**
- **Text boxes, sticky notes and sticky stacks** (fanned, with a count). **[Board]**
- **Frames and lined sheets:** paper frames (lined A4 and others) you can write inside on the endless page. **[Board]**
- **Ruler:** rotate it with two fingers; the pen snaps to the edge and the angle is shown. **[Tools]**
- **Laser pointer:** the trail fades after 1 s and is never saved. Red, green or blue. **[Tools]**
- **Insert menu** with search: **[Insert]**
  - On the page: sticky, sticky stack, text box, paper frame, shape.
  - Files: video, audio, image/photo, PDF, Word, PowerPoint, Excel. Files show a live preview and can be written on.
  - Build on the board: math, graph, table, diagram, timeline, Kanban, website embed.
  - Live widgets: calendar, planner, flashcards, need to remember, chart, clock and date, checklist.
  - Pick files from the tablet, Google Drive, OneDrive, camera or document scan.
- **Whole-board view** with frames, stickies, a Kanban, a timeline, a diagram, a website preview and DOCX/PPTX embeds. **[Board]**

## Phase 4: Import and export
- **Export:** this page, some pages, or the whole notebook.
  - Formats: **PDF** (with a searchable handwriting text layer and an optional dot background) and **board file (.board)**, which is lossless and editable.
  - Endless pages either "fit page to its ink" or split into A4/Letter.
  - Save to the tablet, Google Drive, OneDrive, or the share sheet. **[Export]**
- **Import:** PDF (annotate on top), images, and .board files.

## Phase 5: Handwriting intelligence
- **Handwriting search:** full text across notebooks, with filters for handwriting, typed text, inside PDFs, folder and date. Results show the matched ink highlighted, and "Open at this spot" jumps there. Works offline. **[Search]**
- **Handwriting to text:** lasso, then Convert. Shows a preview with alternatives for words it is unsure of, and a language picker. Then replace the ink, keep the ink too, or copy the text only. There is also "Convert the whole page". **[Convert]**
- **Spell check:** a mode with an "n of m" count, previous/next and "Fix all". Misspellings get a wavy red underline. The suggestion card offers suggestions, **"Fix it in my handwriting"** (re-renders the word in the user's ink style), Look up, Ignore, and Add to my dictionary. **[Spell]**
- **Dictionary and thesaurus** drawer: pronunciation, definitions with examples, synonyms, opposites and recent lookups, plus "Add definition to page" and "Make flashcard". Works offline, for example with bundled WordNet. **[Spell]**

## Phase 6: Math
- **Math mode:** handwriting converts to typeset math as you go.
  - Lasso, then "Convert to math", "Graph it", or "Copy as LaTeX". There is a live preview.
  - The math keyboard has tabs for Greek, Operators, Structures (fractions, roots, integrals, sums, limits, matrices) and Units. **[Math]**
- **Graphs:** 2D (x, y) with multiple functions, handwritten functions, trace, and intersections. 3D (x, y, z) surfaces that you can rotate. **[Graph]**
- **Math tools** **[MathKit]**:
  - **Number line** with points, open or closed intervals, and irrational points (π, √2).
  - **Unit circle** that steps through the 16 special angles with exact sin, cos and tan, with the cos and sin projections colored.
  - **Polar grid** with polar curves, for example r = 1 + cos θ and r = 2 cos 3θ.
  - **Formula library:** Math (quadratic, Pythagorean, circle area, slope, power rule, ∫xⁿ, log rules, identities) and Physics (kinematics, Newton's second law, momentum, KE, PE, work, Ohm's law).
  - **Symbols** keypad, a 4-column grid of large keys: π e φ τ ∞ √ ∫ ∬ ∭ ∮ d/dx d²/dx² ∂/∂x ∇ Σ Π ± × ÷ ≈ ≠ ≤ ≥ ∝ α β γ δ ε θ λ μ σ ω Δ Ω ∈ ∉ ⊂ ∪ ∩ ∀ ∃.
  - Inserting anything shows an "Added … to the page" toast with Undo.

## Phase 7: Widgets, planning and study
- **Calendar:** month, week and day views. Syncs **Google and Outlook** calendars two ways, and each calendar can be toggled. Events link to notes ("Open notes", template). **[Calendar]**
- **Planner:** Today, 3 days or Week. Top 3 today, a to-do list (drag onto the schedule to block time), the schedule, and notes for today. **[Planner]**
- **Widgets on the page:** calendar, planner, flashcards and remember, all live, resizable and movable. **[WidgetBoard]**
- **Flashcards:**
  - **Make:** circle the front, then circle the back (ink, images and typed text all work). Choose a deck and optionally "also quiz me back to front". **[FlashMake]**
  - **Study:** flip or "write the answer", with a progress bar and due count. Scheduling uses FSRS. **[Study]**
- **Need to remember:**
  - Star, lasso, or draw a star next to anything, with an optional "why it matters" note, a reminder (tomorrow, before an event, or a date), and "also make it a flashcard". **[RememberMark]**
  - The Remember section collects every starred item across notebooks, with filters and "Review all". **[Remember]**
- **Charts linked to tables and Excel:** bar, line, area or scatter charts bound to a range such as `Lab data.xlsx › Sheet1 › A1:C7`. They update live, and can be unlinked into a snapshot. Editing the table updates the chart. **[Charts]**
- **Live items** **[LiveItems]**:
  - A live date chip.
  - An analog or digital clock in the device time zone.
  - **Time stamps** that show clock time or "time ago".
  - **Checklists** with a progress bar.

## Phase 8: Audio and video
- **Record audio** from the left rail (Insert menu). The clip can be placed anywhere on the page.
  - While recording, ink is time-stamped; during playback the ink lights up as the recording reaches it, and tapping ink jumps to that moment.
  - Controls are speed, ±10 s, and a waveform.
  - **Transcript** panel with speakers and timestamps: "Add to page as text", Copy, Export. **[Audio]**
- **Video:** upload and play inside notes. Notes can be pinned to moments, and you can grab a frame, trim, transcribe or replace. Large videos stay in Drive and the page keeps a link. **[Video]**

## Phase 9: Cloud, sharing and collaboration
- **Sync settings:**
  - Google Drive and/or OneDrive, with a chosen folder.
  - What syncs: board files, optional PDF copy, images and PDFs.
  - Wi-Fi only.
  - Conflict policy: "Merge both", where strokes never overwrite each other. **[Sync]**
- **Share:** this page, the notebook or a folder. Invite by email as Can edit or Can comment. Link access is Off, Can view, Can comment or Can edit. Or send a copy as PDF, board file or image. Locked content can't be shared. **[Share]**
- **Live collaboration:** presence avatars, live cursors labelled "Maya · writing", comment threads on ink, and offline edits that sync later. **[Live]**

## Phase 10: Polish and more devices
- Dark mode check on every screen (**[CanvasDark]**), plus High contrast.
- Version history, sync conflict UI, and crash recovery screens. These are not designed yet; ask the owner first.
- Phone layout, then Windows, Linux and web.
