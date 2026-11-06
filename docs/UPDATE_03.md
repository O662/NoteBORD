# Update 03: window view and the Endless logo

Build this after Update 02. The screenshots and markup in `design/` are already updated.

## 1. Window view

A floating window that shows another part of the same note, another page, or another note, while you keep writing in the main page. It works like split view, but it floats over the page.

Screens: `Window.png`, `Window-faded-resized.png`, `Window-source-picker.png`, `Window-other-note.png`, `Window-bubble.png`, `Canvas-view-menu.png`. Exact behavior is in `design/source/Window.dc.html`: the window markup is at the end of the file, and the window state starts at `win:` in the component.

- **Opening it:** Ruler, laser & view menu → Window view (`Canvas-view-menu.png`). A few windows at once would be nice later; one is enough for now.
- **Move it anywhere:** drag the title bar (⋮⋮ grip). It stays on screen (at least 120 dp visible). The lock (pin) button stops it moving by accident.
- **Resize it:** drag the dark corner handle at the bottom-right. Minimum 340×200, maximum 960×700.
- **Opacity:** the slider in the window's footer goes from 25% to 100%. Only the window's paper and ink fade; the title bar and footer stay readable.
- **What it shows:** tap the title to pick:
  - a different spot on this page (it remembers where you panned to),
  - another page in this notebook,
  - another note (recent ones are listed, plus "Find another note…", which opens search).
- **Inside the window:** drag with a finger to pan, pinch or use − and + to zoom (50–200%).
- **Pen: page / Pen: window:** chooses where the S Pen writes. By default the window is read-only so you don't write in it by accident. When it's on, the window shows a "Pen writes here" tag.
- **Swap (⇄):** swaps what's in the window with the main view.
- **Split view button:** turns the window into a split view.
- **Shrink (–)** turns it into a small bubble with the note's title, in the same spot. Tap the bubble to open it again.
- **Close (×)** closes it.
- **Saved per notebook:** the window's position, size, opacity and source are saved, so it comes back where you left it.

## 2. Logo and app icon

The logo is an infinity arrow: an infinity symbol drawn as one ink stroke that never closes. It starts just inside the right loop, goes all the way around, and the rising center line comes back out past its own start as an arrow, pointing up and to the right. It stands for never ending and always moving forward. See `Logo.png`.

The files are in `design/logo/`:

| File | Use |
|---|---|
| `endless-icon-paper.svg` | Main app icon (light) |
| `endless-icon-night.svg` | Dark variant |
| `endless-icon-ink.svg` | Store listings and promo |
| `endless-icon-mono.svg` | White on black, for one-color uses |
| `endless-mark-foreground.svg` | Android adaptive icon foreground. The mark is scaled to fit the 66% safe zone; use background color `#F6F1E7` |
| `endless-mark-notification.svg` | Android notification (status bar) icon, white on transparent |

- Colors: black ink `#0C0C0C` on paper `#F6F1E7` (the main icon). Dark mode: `#EEE8DC` on `#1C1A17`. Store/promo: `#F6F1E7` on blue `#2B5A8C`. Mono: white on `#0C0C0C`. The mark is always one color.
- Tagline: “A Notebook Built for Students, by Students” (shown under the wordmark in Caveat).
- The library sidebar logo (Start, Main, Calendar, Planner, Remember, Sticky notes, New note) is now this mark beside "Endless" in Newsreader.

## Prompt to paste into Claude Code

```
Read docs/PROGRESS.md first, then docs/UPDATE_03.md. Update 02 should already be built;
if it isn't, build that first.

This is my request: build Update 03.
1. Window view, matching design/screens/Window*.png and design/source/Window.dc.html: a
   floating window you can drag anywhere, lock in place, resize from the corner, fade with
   the opacity slider, and pan/zoom inside. It can show another spot on this page, another
   page or another note, with swap, open as split view, shrink to a bubble and close, plus
   the Pen: page / window switch. Open it from the Ruler, laser & view menu, and save its
   state per notebook.
2. The new logo: use design/logo/ for the Android launcher icon (adaptive icon: the
   foreground SVG on #F6F1E7, plus a monochrome layer for themed icons), the notification
   icon, the splash screen and the sidebar logo. Generate the PNG sizes Android needs.
Update docs/SPEC.md and docs/SCREENS.md, plan first, then build, run flutter analyze and the
tests, update PROGRESS.md, commit and push. Give me a short tablet checklist.
```
