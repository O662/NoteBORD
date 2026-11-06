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
  - **Swipe up to tuck it away** (or tap its handle): it tucks into the tool bar, and a small pull tab with three of its colors hangs under the tool bar. Pull the tab down (or tap it) to bring the tray back. The pen settings panel has a "Swipe up to tuck away" handle too. Settings › Pen & S Pen › "Swipe up to tuck menus away" turns both off. **[Canvas-colors-tucked, Canvas-pen-settings]**
- **Zoom** pill in the bottom-right corner: −, %, +, a "show map" button when the map is hidden, whole board, and **full screen** (hides every menu except this pill). Pinch zoom and two-finger pan also work. **[Canvas, Canvas-fullscreen]**
- **Page bar** in the bottom-left corner (Update 02, replacing the pages rail on the right). Left to right: previous page; the page's color dot, title and "3 of 12" (tap for the preview); next page; then **Preview**, **All pages** and the **⋯ page menu**. **[Canvas]**
  - **Preview** (up arrow): a card with the whole page, its title, "Page 3 of 12 · edited 2 hours ago", and buttons for the previous and next page. **[Canvas-page-preview]**
  - **All pages** (grid): a strip of every page's thumbnail above the bar, with the page colors, a lock badge, Add page and Hide. Tap the grid again to turn it off. A long press drags a page to reorder it. **[Canvas]**
  - **⋯ page menu:** Preview, Rename (edits the title right in the bar), Edit page (paper and template; also ⋯ → Page & paper), Duplicate, Move to… (another notebook), Page color (7 colors plus none) and Delete page. Duplicate, Move and Delete show a toast with Undo. A locked page's menu has Preview only. **[Canvas-page-menu, Canvas-page-move, Canvas-page-rename]**
- **Map**: a minimap of the endless page. It sits directly above the zoom pill, right-aligned and the same width (236 dp). It can collapse, and the zoom pill then gets a "show map" button. **[Canvas, Canvas-map-hidden]**
- **Left rail** (floating, compact), vertically centered on the left edge (top 274 dp on a 1280×800 screen): 4 group buttons and Search. Each group button has a small corner tick to show it opens a menu. **[Canvas, Canvas-rail-hover-insert, Canvas-rail-pinned]**
  - **Insert** (blue +): Sticky note, Paper frame, Image, Record audio, Templates, Everything else (the full Insert menu).
  - **Study & math** (cap icon): Need to remember, Make flashcards, Math & graphs, Math tools.
  - **Writing help** ("abc✓" icon with a red squiggle): Spell check, Dictionary & thesaurus, Convert to text.
  - **Ruler, laser & view**: Ruler, Laser pointer, Split view, Window view (Update 03). **[Canvas-view-menu]**
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
  - An arrow or straight line that starts or ends on a shape, sticky note, frame, card or other item snaps to its edge (with a small dot) and stays attached when the item moves or is resized. Dragging the end away lets go.
- **Scribble to erase:** scribbling over ink erases only the strokes under the scribble. Sensitivity is Light, Normal or Firm. **[Scribble]**
- **Text boxes, sticky notes and sticky stacks** (fanned, with a count). **[Board]**
- **Sticky pads:** a pad of notes on the page. Drag a note off it with the pen or a finger, as many as you like; each is an ordinary sticky note. Held over another note for a moment, the new note stacks onto it when let go. *(Added at the owner's request, 2026-11-04; no design screen.)*
- **Frames and lined sheets:** paper frames (lined A4 and others) you can write inside on the endless page. **[Board]**
- **Ruler:** rotate it with two fingers; the pen snaps to the edge and the angle is shown. **[Tools]**
- **Laser pointer:** the trail fades after 1 s and is never saved. Red, green or blue. **[Tools]**
- **Insert menu** with search: **[Insert]**
  - On the page: sticky, sticky stack, sticky pad, text box, paper frame, shape.
  - Files: video, audio, image/photo, PDF, Word, PowerPoint, Excel. Files show a live preview and can be written on. (Word, PowerPoint and Excel previews were built in Phase 4b, after PDF import.)
  - Build on the board: math, graph, table, diagram, timeline, Kanban, website embed.
  - Live widgets: calendar, planner, flashcards, need to remember, chart, clock and date, checklist.
  - Pick files from the tablet, Google Drive, OneDrive, camera or document scan.
- **Whole-board view** with frames, stickies, a Kanban, a timeline, a diagram, a table and a website preview. **[Board]** (The DOCX, PPTX and XLSX cards on that screen came in Phase 4b.)

## Phase 4: Import and export
- **Export:** this page, some pages, or the whole notebook.
  - Formats: **PDF** (with a searchable handwriting text layer and an optional dot background) and **board file (.board)**, which is lossless and editable.
  - Endless pages either "fit page to its ink" or split into A4/Letter.
  - Save to the tablet, Google Drive, OneDrive, or the share sheet. **[Export]**
- **Import:** PDF (annotate on top), images, and .board files.
- **Office files on the board:** Word, PowerPoint and Excel previews (the Insert menu's file tiles, and the DOCX, PPTX and XLSX cards on **[Board]**). Moved here from Phase 3, because they share PDF import's file picking and rendering.

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
- **Calendar:** month, week and day views. Shows **Google and Outlook** calendars, and each calendar can be toggled. Events link to notes ("Open notes", template). **[Calendar]**
  - **For now, calendar sync is read-only: calendar links, view only** (the owner's choice, 2026-11-04). Paste a calendar's private iCal (.ics) address; its events show and refresh, nothing is sent back, and no account or cloud project is needed.
  - **Deferred to Phase 9: two-way sync** with Google and Outlook sign-in (setup in docs/CLOUD_SETUP.md). Nothing in Phase 7 or 8 writes to Google or Outlook.
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
  - Recording keeps going with the screen off or another app in front, and the audio is kept in the `.board` package.
  - **Transcripts are made on the device, offline and free** (the owner's choice, 2026-11-04): whisper.cpp for the words (99 languages), pyannote and SpeechBrain models on ONNX Runtime for telling speakers apart. No code from companies that must share data with a government (no sherpa-onnx). See tool/speech_model/README.md. *(Phase 8a)*
- **Video:** upload and play inside notes. Notes can be pinned to moments, and you can grab a frame, trim, transcribe or replace. Large videos stay in Drive and the page keeps a link. **[Video]**
  - *(Phase 8b)* For now, large videos (over 100 MB) stay on the tablet and the page keeps a link; moving them to Google Drive comes with Phase 9. Trim keeps where to start and stop (the file isn't cut).

## Phase 9: Cloud, sharing and collaboration
- **Two-way calendar sync** with Google Calendar and Outlook (deferred from Phase 7, where calendars are read-only links): sign in, edit events in Endless and send the changes back. **[Calendar]**
- **Sync settings:** *(Phase 9a, built 2026-11-05)*
  - Google Drive and/or OneDrive, with a chosen folder.
  - What syncs: board files, optional PDF copy, images and PDFs.
  - Wi-Fi only.
  - Conflict policy: "Merge both", where strokes never overwrite each other. **[Sync]**
  - The title pill shows Saving… / Saved / Saved on this tablet / Synced to Google Drive; the library sidebar shows the last sync. *(9a)*
  - Big videos move to Drive or OneDrive and the page keeps a link (Video.png's upload card). *(9a)*
  - Version history from the ⋯ menu: earlier versions of a page, restore one (the owner asked for it in 9a, ahead of Phase 10; no design, so a plain dialog). *(9a)*
- **Share, without a server** *(Phase 9b, built 2026-11-06)*: this page, the notebook or a folder, sent as a PDF, board file or image through the share sheet (Gmail, Drive, OneDrive, messages…). Opening a shared board file in Endless imports it. Pages with a password are never sent, not even sealed. Invites, link access and live editing show as "Coming later". **[Share]**

## Update 02: tablet refinements (docs/UPDATE_02.md)
- **Settings** is one screen (**[Settings, Settings-pen, Settings-notebooks, Settings-search]**): a side menu with every section (General, Account, Pen & S Pen, Handwriting & search, Notebooks & pages, Sync & backup, Themes & dark mode, Notifications, Calendar, Storage, Privacy & security, About) and a search box that finds any setting by its name or description ("Pen & S Pen › Menus"). Sync & backup (**[Sync]**) and Themes & dark mode (**[Themes]**) are panels in it, with a chevron in the menu. ⋯ → Settings and the library sidebar's gear open it; the sidebar's sync card opens Sync & backup.
  - **Themes & dark mode:** Light / Dark / Match tablet, the 7 themes (Paper, Midnight, Sage, Blush, Graphite, High contrast, Harbor), the accent (Theme default or one of 7), the default paper, "Keep pages light in dark mode", and a live preview of a page and the library. Every screen follows. A theme's full palette is made from its 7 colors in design/tokens.json the way Paper's palette is made from Paper's; colors that mean something (clay, green, record, the laser…) are the same in every theme. "Make my own" comes later.
- **New note** (**[NewNote]**), from Start and the Library: the name (written or typed), a folder tree with New folder (nested), Save to (This tablet only, Google Drive or OneDrive; a cloud that isn't connected is signed in to first), paper (or Use a template…), the cover color, "Will be saved as", and "Make these my defaults". Settings › Notebooks & pages › "When I create a new note: Use my defaults" skips the dialog.
- **Where a notebook is saved:** each notebook has its own place (This tablet only, Google Drive or OneDrive). New ones get Settings › Notebooks & pages › "Save new notes to"; the library's notebook menu has **Save to…**. Sync only sends a notebook to its own place; one moved elsewhere tells the cloud it left once, so other devices stop syncing it there too, and the copy already in that cloud stays. Its big videos go to its cloud, or nowhere for This tablet only. The title pill says "Saved on this tablet" for one that stays on the tablet.
- **Sticky notes** in the library (**[Stickies, Stickies-stack]**), under Remember in the sidebar with a count: every sticky note in every notebook with its handwriting and color and the notebook and page it's on (a tap there opens it at that spot). Stacks are fanned cards with "Stack · 5"; a tap opens all their notes, with Open on the page. Filters: All / Stacks / Loose notes, the paper colors, a notebook, and a search of what's written on them (handwriting recognition and typed text). They come from the index, so they're the notes as their pages have them: writing on one on its page changes it here. Notebooks and pages with a password are left out, and a line under the notes says how many.
- **Page bar** and **tucking the pen menus away**: see Phase 1.

## Update 03: window view and the Endless logo (docs/UPDATE_03.md)
- **Window view** (**[Window, Window-faded-resized, Window-source-picker, Window-other-note, Window-bubble]**): a floating window over the page showing another spot of this page, another page of this notebook, or another note, while you keep writing on the page. Opened from Ruler, laser & view → Window view (one window for now).
  - Drag the title bar (⋮⋮) anywhere; at least 120 dp stays on screen. The pin locks it in place. The dark corner resizes it (340 × 200 to 960 × 700). The footer's slider fades its paper and ink (25–100%); the bars stay solid.
  - Tap the title to pick what it shows (recent notes, or Find another note…). A finger pans inside it; pinch or − and + zoom (50–200%).
  - **Pen: page / Pen: window:** where the S Pen writes. Read-only by default; with Pen: window it says "Pen writes here", and a pen tap on the page switches back.
  - Swap (⇄) with the main view, Open as split view, Shrink (–) to a bubble with the note's title (tap to open it again), and Close (×).
  - Its place, size, opacity and what it shows are saved per notebook on the tablet, so it comes back where you left it.
- **Logo and app icon** (**[Logo]**): the infinity arrow, from design/logo/: the Android launcher icon (adaptive, with a monochrome layer for themed icons), the notification icon, the splash screen, and the sidebar's mark beside "Endless" in Newsreader.

## Later
**Needs a backend** (Supabase recommended, or a Cloudflare relay for end-to-end encryption) **and a security review before any real users' data is stored.** The owner's decision (2026-11-06): no server holds anyone's notes for now. Options compared in Phase 9b: Supabase (managed, open source, can be self-hosted later), our own relay on Cloudflare (can be end-to-end encrypted), Firebase (rejected: no Windows or Linux database).
- **Invites:** by email, as Can edit or Can comment, with the people who have access and their state ("In this notebook now", "Last opened yesterday", "Invite sent · waiting"). **[Share]**
- **Link access:** Off, Can view, Can comment or Can edit. Locked content can't be shared by link. **[Share]**
- **Live collaboration:** presence avatars ("3 here"), live cursors labelled "Maya · writing", and offline edits that sync later (the item-level merge from Phase 9a carries over). **[Live]**
- **Comments:** threads on ink, replies written or typed, Resolve. **[Live]**

## Phase 10: Polish and more devices
- Dark mode check on every screen (**[CanvasDark]**), plus High contrast.
- Sync conflict UI and crash recovery screens. These are not designed yet; ask the owner first. (Version history came in Phase 9a, as a plain dialog; it may get a design here.)
- Phone layout, then Windows, Linux and web.

## Before release
Endless can't be sold until this is done.

- **Replace the handwritten-math recognizer.**
  - **The problem:** Math mode reads handwriting with CoMER, an open model, and its weights are for **personal, non-commercial use only**. The checkpoint was trained on CROHME, which is CC BY-NC-SA, and so was every open handwritten-math model checked in Phase 6a.
  - **Options:**
    - **MyScript iink:** commercial, works on the device and offline, licensed per app.
    - **A model of our own:** trained only on data whose licence allows commercial use, for example handwriting we collect with consent.
  - **Requirement:** whatever replaces it must still work offline and on every platform, or say clearly where it doesn't.
  - **What changes:** the app only reads math through the `MathModel` interface (`lib/math/decoder.dart`). A replacement model can be two ONNX files with the same inputs and outputs (`tool/math_model/README.md`). A different engine needs its own `MathReader` backend.
  - **Also:** remove CoMER's notice from the licence page (`assets/math/NOTICE.txt`) and the weights from `assets/math/`.
- **Check every other bundled licence again.** The fonts (OFL), the dictionary and word lists (`assets/dictionary/NOTICE.txt`), the packages, and ML Kit's terms must all allow selling the app.
