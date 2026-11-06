# Update 02: tablet refinements

These are design changes from using the app on the tablet. The screenshots and markup in `design/` are already updated.

## What changed

1. **Settings page.** There is now one Settings screen (`Settings.png`, plus `Settings-pen.png`, `Settings-notebooks.png` and `Settings-search.png`).
   - Sections: General, Account, Pen & S Pen, Handwriting & search, Notebooks & pages, Sync & backup, Themes & dark mode, Notifications, Calendar, Storage, Privacy & security, About.
   - A search box finds any setting.
   - Sync & backup and Themes & dark mode keep their existing screens, and their side menus now list every section.
   - The ⋯ menu's Settings item and the gear in the library sidebar open it.
2. **Page bar in the bottom-left** replaces the pages rail on the right (`Canvas.png`, `Canvas-page-preview.png`, `Canvas-page-menu.png`, `Canvas-page-move.png`, `Canvas-page-rename.png`). From left to right it has:
   - Previous page.
   - The page's color dot, title and "3 of 12". Tapping it opens the preview.
   - Next page.
   - **Preview** (up arrow): a card with the whole page, its title, when it was edited, and the previous and next page.
   - **All pages** (grid): a strip of every page's thumbnail above the bar, with page colors, a lock badge, Add page and Hide. Tap it again to turn it off. Pages can be dragged to reorder.
   - **⋯ page menu:** Preview, Rename (edits the title right in the bar), Edit page (paper, template, background), Duplicate, Move to… (pick another notebook), Page color (8 swatches plus none), and Delete page. Duplicate, Move and Delete show a toast with Undo.
3. **Left tool menu is vertically centered** on the left edge (top 274 dp on a 1280×800 screen). Its flyouts still open beside the button you hover or tap.
4. **Swipe to tuck the pen menus away** (`Canvas-colors-tucked.png`, `Canvas-pen-settings.png`):
   - The extra colors tray under the tool bar has a handle. Swipe it up (or tap it) and the tray tucks into the tool bar.
   - A small pull tab with three color dots then hangs under the tool bar. Pull it down (or tap it) to bring the tray back.
   - The pen settings panel also has a "Swipe up to tuck away" handle at the bottom.
   - This can be turned off in Settings › Pen & S Pen.
5. **New note dialog** (`NewNote.png`), opened from New note on the Start page and in the library. It has:
   - Name (write it or type it).
   - Folder tree with New folder, which can be nested.
   - Save to: This tablet only, Google Drive or OneDrive (OneDrive asks you to sign in first).
   - Paper (Dots, Lines, Grid, Blank or a template) and cover color.
   - A "Will be saved as" path preview, a "Make these my defaults" checkbox, and Cancel and Create note.
   - Settings › Notebooks & pages has "When I create a new note: Ask for name and location / Use my defaults". With "Use my defaults", New note skips the dialog.
6. **Sticky notes section** (`Stickies.png`, `Stickies-stack.png`) is a new library sidebar item under Remember, with a count.
   - It shows every sticky note across all notebooks, with its handwriting, its color, and which notebook and page it's on. Tapping that location opens the note at that spot.
   - Stacks show as fanned cards with a "Stack · 5" badge. Tapping one opens all its notes, with "Open on the page".
   - Filters: All / Stacks / Loose notes, by color, by notebook, and searching what's written on them (using handwriting recognition).
   - Notes stay linked to their page, so editing one in either place updates both.

Also updated to match: `CanvasDark.png` (page bar, centered menu), and the centered menu on `Audio.png`, `Live.png`, `Split.png` and `WidgetBoard.png`. The library sidebars on Start, Main, Calendar, Planner and Remember gained the Sticky notes item.

## Prompt to paste into Claude Code

```
Read docs/PROGRESS.md first, then docs/UPDATE_02.md.

This is my request: build Update 02, the tablet refinements. Match the screenshots listed in
UPDATE_02.md and use design/source/ for exact sizes, labels and behavior:
1. The bottom-left page bar (previous/next, title + preview, all-pages strip, ⋯ page menu with
   preview, rename, edit page, duplicate, move, page color, delete), replacing the right pages rail.
2. Center the left tool menu vertically.
3. Swipe up to tuck the colors tray and the pen settings panel away, and a pull tab to bring
   the tray back. Respect the new setting.
4. The full Settings screen with all sections and search, wired to the settings that already
   exist. Settings that don't do anything yet are saved, and the update notes say which.
5. The New note dialog with name, folder tree, new folder, save location, paper, cover and
   "make these my defaults", plus the Settings option to skip it.
6. The Sticky notes section in the library, with stacks, filters, search and "open at this spot".
Update docs/SPEC.md and docs/SCREENS.md to describe these, plan first, then build, run flutter
analyze and the tests, update PROGRESS.md, commit and push. Give me a short tablet checklist.
```
