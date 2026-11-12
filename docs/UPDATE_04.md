# Update 04: Phase 10 polish, new notebooks, printing and portrait

Build this after Update 03. Screenshots are in `design/screens/`, and the markup and exact behavior are in `design/source/` (each `.dc.html` has its state and logic at the end of the file, in the `Component` class).

## 1. Share a copy (`Share.png`, `Share.dc.html`)

Sharing only sends a copy for now. Live collaboration stays off until it can be done securely.

- **What to share:** This page / Notebook / Folder.
- **Format:**
  - **PDF:** option to make handwriting searchable (on by default) and option to include the paper background.
  - **Board file (`.board`):** option to include audio and video.
  - **Image (PNG):** "This page" only. It is greyed out for Notebook and Folder.
- **Send with:**
  - The Android share sheet.
  - Google Drive.
  - OneDrive.
  - Save to tablet, using the system file picker (SAF).
- **Locked pages are never included.** The dialog says which ones are left out.
- The "Invite people and write together" card is a disabled placeholder marked "Coming later". Don't build any sharing backend.
- The footer shows the scope, page count and an estimated size.

## 2. Sync conflict (`Conflict.png`, `Conflict.dc.html`)

This screen appears when the same page was edited on two devices while one was offline.

- The two versions are shown side by side.
  - Each card has the device, time and a one-line summary of what's only on that side.
  - What's only on each side is highlighted: green for this tablet, blue for the other device.
- **Choices:**
  - **Merge both (default):** a union of strokes. Moved items take the newest position.
  - **Keep this tablet's.**
  - **Keep the phone's.**
  - **Keep both as pages:** the other version is inserted right after this page.
- **Nothing is ever lost.** The version you don't keep goes into version history for 30 days.
- **"Decide later"** keeps both and shows a chip with the count of pages to check, e.g. "1 of 2 pages to check". Sync never blocks writing.

## 3. Crash recovery (`Recovery.png`, `Recovery.dc.html`)

- Write strokes to a local journal file as you write: append-only, flushed about every 2 seconds and when the app is paused.
- On the next launch after an unexpected exit, replay the journal onto the page. Then show the card "We brought back your last strokes" with:
  - When the app closed and how much was recovered.
  - **Show what came back** (default on): green dashed highlights with a "BROUGHT BACK" tag.
  - **Undo restore / Redo restore.**
  - **Send an anonymous crash report.** Off by default and never includes notes or handwriting.
  - **Keep writing** dismisses the card.

## 4. Version history (`History.png`, `History-naming.png`, `History.dc.html`)

- Versions are saved automatically as you write, grouped by day.
  - Each entry shows the time, device and a change summary, e.g. "+12 strokes · 1 image".
  - A merge from another device is its own entry.
- **Preview:** shows the page at that version.
  - **Show changes** marks what that version added (green, "ADDED") and what was erased later (terracotta, struck through).
- **Restore this version:** today's page is saved as a version first, and an Undo toast appears.
- **Save as a new page:** puts that version after the current page.
- **Name this version:** named versions are kept until deleted; unnamed ones for 30 days. The filter switches between All versions and Named only.
- **Opening it:** ⋯ menu › Version history, which now opens `History.dc.html`.

## 5. Collapsible home header (`Start.png`, `StartCollapsed.png`)

- The Collapse button on the greeting folds the greeting and the 5 big action tiles into one slim bar:
  - "Welcome back", New note, Notebook, plus the Template, Import and Scan icons.
  - An expand chevron.
- Collapsed, the page shows more Recent notebooks (2 rows instead of 1).
- Remember the choice across launches.

## 6. New notebook prompt, with skip (`NewNotebook*.png`, `LibraryUnset*.png`, `FinishSetup.png`)

**When it appears:** "New notebook" on Start and in the Library now opens `NewNotebook.dc.html`. It asks three quick things:

1. **Name** and cover color.
2. **Where it lives:** a folder, plus where it's saved (This tablet / Google Drive / OneDrive). OneDrive asks you to sign in first if it isn't connected.
3. **Back it up?**
   - Saved to the cloud: it's already backed up and the switch is locked on.
   - Saved on this tablet: the switch picks between "Back up to Google Drive" and "No backup". With No backup, a clear warning says the notebook is lost if the tablet is.

**Skipping and finishing later:**

- **Skip for now** creates "Untitled notebook" right away (on this tablet, no folder, no backup) so a student in a rush can just write.
  - A skipped notebook shows a **"Not set up"** tag in the library.
  - Its ⋯ menu gets **Finish setting up** at the top, which opens the same three steps (`FinishSetup.png`).
  - That item is hidden for notebooks that are set up (`LibraryUnset-other-menu.png`). Show it in the canvas ⋯ menu the same way.
- **Use these every time and stop asking** saves the choices as defaults and skips the prompt from then on. It can be undone in Settings › New notebooks (add that row).

## 7. Print layout: drag page boxes over the board (`PrintLayout*.png`, `PrintLayout.dc.html`)

This replaces the old print flow. ⋯ › Print… opens it.

**The board:**

- The board is shown zoomed out, with page-shaped boxes on top.
- **What's inside a box prints on that page.** Boxes are numbered in print order.
- Drag a box to move it, and drag its corner handle to resize it (it keeps the paper's shape).
- The selected box has a × to remove it.
- **A bigger box means smaller ink on paper.** The panel shows the scale, e.g. "prints your ink at 107% of its real size".

**Anything not covered by a box:**

- It gets a dashed terracotta outline and a "NOT ON A PAGE" tag.
- The panel warns about it and offers **Add pages for them**.
- When everything is covered, it says so in green.

**Side panel:**

- Paper: A4 or US Letter.
- Portrait or Landscape for the selected page.
- A page list with live thumbnails of what's on each page.
- On every page: title and date, page numbers, dot grid background.
- **Save as PDF** and **Print N pages**, which go to the Android print service.

**Also:**

- "Add a page" and "Lay out pages for me", which auto-places boxes over all the ink.
- The layout is saved with the notebook, so printing again reuses it.

## 8. Portrait (`StartPortrait.png`, `StartPortraitMenu.png`, `CanvasPortrait*.png`)

Design for 800×1280 dp, and switch layouts with the window size, not the device. The rules for portrait (narrower than about 900 dp):

**Canvas:**

- Row 1: title pill on the left, Share and ⋯ on the right.
- Row 2: the writing-tools pill, centered.
- The color tray and pen popover open under row 2.
- The left rail moves to the vertical center of the screen.
- The page bar stays bottom-left and the zoom pill bottom-right.
- The map starts collapsed (map button in the zoom pill), and the All pages strip starts closed.
- Floating panels and the window view are no wider than 92% of the screen.

**Library and Start:**

- The sidebar becomes a drawer, opened from the ☰ button in a 72 dp top bar. The top bar also has search, sync status and settings.
- Home tiles stay 5-across but shorter.
- Pinned goes to a row of 3.
- Recent and notebook grids go to 2 columns.

**Dialogs:**

- Width is min(680 dp, screen − 32 dp).
- Folder chips wrap.
- Footer buttons stack if they don't fit.

**Never let things overlap.** Collapse first: hide labels and keep icons, then move items into the ⋯ menu.

## 9. Collapsible sidebar (`CalendarRail.png`, `StickiesRail.png`, `*-rail.png`)

The left sidebar (Home, notebooks, Calendar, Flashcards, Remember, Sticky notes, Trash, folders, sync) can fold down to give pages like Calendar more room. Exact markup: the `navClosed` block in `CalendarRail.dc.html`.

- **Collapse:** the sidebar button next to the Endless logo shrinks the 272 dp sidebar to an **80 dp icon rail**.
- **The rail keeps everything reachable:**
  - Expand button, then Search.
  - Each section as an icon with a short label (Home, Notebooks, Calendar, Cards, Remember, Stickies, Trash). The current section is highlighted.
  - Badges stay visible: 5 cards due, 8 to remember.
  - Folders as colored folder icons.
  - At the bottom, sync status (a cloud icon; tap it for sync details) and Settings.
- **Content reflows into the freed 192 dp.** For example, the Calendar week columns get wider, so event titles fit on one line. Planner, Sticky notes, Remember and the Library grids just get wider.
- **It's one app-wide setting**, remembered across launches, so if you collapse it in Calendar it stays collapsed everywhere until you expand it.
- On screens narrower than about 900 dp (portrait), use the slide-out drawer from section 8 instead of the rail.

## 10. Your shortcuts on the canvas toolbar (`CanvasShortcuts*.png`, `Canvas-pin-from-menu.png`, `Canvas-shortcuts-in-use.png`, `CanvasPortrait-shortcuts.png`)

The left toolbar on the writing page now has a section the student controls. They can put the tools they use most there, such as Record audio, PDF, Website or the Ruler, so they don't have to dig through menus. Exact behavior: `design/source/CanvasShortcuts.dc.html`. The logic starts at `// ---------- your shortcuts` and the panel markup is at the end of the file.

**How the toolbar is laid out:** the 4 built-in menus (Insert, Study & math, Writing help, Ruler, laser & view), a divider, **up to 6 shortcuts**, a divider, Search, and the dashed **Your shortcuts** button.

**What a shortcut does:**

- **Tools** (Ruler, Laser, Sticky note, Image, Paper frame) switch on in place. A tool that's on shows dark, and tapping it again goes back to the pen.
- **Everything else** opens that feature directly: PDF, Audio, Video, Website, Table, Chart, Checklist, Time stamp, Templates, Remember, Flashcards, Math, Graph, Math tools, Spell check, Dictionary, Convert to text, Split view, Window view, Print, Export, Version history.

**Two ways to add a shortcut:**

1. **Pin from any toolbar menu.** Each menu item has a pin on its right. Tap it to add the item, and tap the filled pin to remove it. When all 6 spots are full, the pins grey out and say so.
2. **The Your shortcuts panel** (the dashed button at the bottom of the toolbar):
   - **Left side:** what's on your toolbar ("3 of 6"), with move up and move down, remove, empty spots, and **Reset to the default** (Record audio, PDF, Ruler).
   - **Right side:** every available tool grouped (Insert, Study & math, Writing help, Tools & view), with a search box ("website", "ruler", "PDF") and **+ Add** / **✓ Added** buttons. When the toolbar is full, the buttons show **Full**.
   - A tip at the bottom points to the pins. **Done** closes the panel.

**Where it sits:**

- The toolbar stays centered vertically and grows or shrinks with the number of shortcuts.
- It stays clear of the bottom panels. With the All pages strip open, it moves up above the strip. While the page preview or page menu is open, it hides.
- In portrait it centers on the taller screen.

**Saving:** shortcuts are saved per user (not per notebook) and sync with their settings. Add Settings › Writing › "Toolbar shortcuts", which opens the same panel.

## Prompt to paste into Claude Code

```
Read docs/PROGRESS.md first, then docs/UPDATE_04.md. Update 03 should already be built;
if it isn't, build that first.

This is my request: build Update 04, matching design/screens/ and design/source/.
1. Share a copy (copy only: PDF / board file / image via the share sheet, Drive, OneDrive
   or Save to tablet; locked pages left out; "Invite people" shown as Coming later, no
   sharing backend).
2. Sync conflict screen (merge both by default, keep one side, or keep both as pages; the
   version not kept goes into history; "Decide later" never blocks writing).
3. Crash recovery: an append-only stroke journal, replayed on the next launch, with the
   "We brought back your last strokes" card, highlights, undo restore, and an opt-in
   anonymous crash report that never includes notes.
4. Version history: automatic versions grouped by day, preview with Show changes,
   restore (saves the current page as a version first), save as a new page, and name a
   version (named versions are kept, others 30 days).
5. A collapsible header on the Start page, remembered across launches.
6. A new notebook prompt (name + color, folder + save location, backup) with Skip for now,
   which makes "Untitled notebook" with a "Not set up" tag and a "Finish setting up" item
   in its ⋯ menu that's hidden once it's set up. "Use these every time" saves defaults;
   add Settings › New notebooks.
7. Print layout: draggable, resizable page boxes over a zoomed-out board, numbered in
   print order, A4/Letter, portrait/landscape per page, "not on a page" warnings with
   "Add pages for them", auto layout, thumbnails, header/page numbers/background options,
   Save as PDF and Print via the Android print service. Save the layout per notebook.
8. Portrait layouts using the rules in UPDATE_04 section 8 (switch by window width), for
   the canvas, Start, the library and dialogs.
9. A collapsible app sidebar (section 9): a collapse button next to the logo shrinks it to
   an 80 dp icon rail with labels, badges, folders, sync and settings, and the page content
   reflows wider. One app-wide setting, remembered across launches.
10. Your shortcuts on the canvas left toolbar (section 10): up to 6 user-chosen tools
    between the built-in menus and Search; a pin on every toolbar menu item to add or
    remove it; a "Your shortcuts" panel with reorder, remove, reset, search and a grouped
    catalog. Tools toggle in place, features open directly. The toolbar re-centers and
    stays clear of the bottom panels. Save per user and sync; add Settings › Writing ›
    Toolbar shortcuts.
Update docs/SPEC.md and docs/SCREENS.md, plan first, then build, run flutter analyze and the
tests (add tests for the conflict merge, journal replay, and print box coverage), update
PROGRESS.md, commit and push. Give me a short tablet checklist, including rotating the
tablet on every main screen.
```
