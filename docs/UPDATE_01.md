# Update 01: canvas chrome cleanup

Feedback from testing build 1 on the tablet. The design and docs in this repo are already updated.

## What changed
1. **Spell check and dictionary** moved out of the top bar into the left rail, under a "Writing help" menu.
2. **Share replaces Export** in the top-right pill.
   - Share is now the dark filled button.
   - Export moved into the Share dialog ("Export a copy" row) and the ⋯ menu.
   - Password protect also moved into ⋯.
3. **Compact left rail.** Four group buttons (Insert, Study & math, Writing help, Ruler/laser/view) plus Search. Each group opens a menu:
   - **Hover** (S Pen hover or mouse) previews the menu. It closes when the pointer leaves.
   - **Tap** pins the menu open until you tap outside, tap the button again, or pick an item.
4. **Map and zoom.** The map sits above the zoom pill, both right-aligned in the bottom-right corner.
   - The zoom pill has −, %, +, whole board, and **full screen**, which hides all menus except the zoom pill.
   - When the map is hidden, a map button appears in the zoom pill.

Screens: `Canvas.png`, `Canvas-rail-hover-insert.png`, `Canvas-rail-pinned.png`, `Canvas-more-menu.png`, `Canvas-map-hidden.png`, `Canvas-fullscreen.png`, `Share.png`, `CanvasDark.png`.
Exact layout and values: `design/source/Canvas.dc.html`, where the `G` array holds the menu groups and `moreItems` holds the ⋯ menu.

## Prompt to paste into Claude Code

```
Read docs/UPDATE_01.md, the updated left rail and top-right sections of docs/SPEC.md,
and look at design/screens/Canvas.png, Canvas-rail-hover-insert.png, Canvas-rail-pinned.png,
Canvas-more-menu.png, Canvas-map-hidden.png, Canvas-fullscreen.png and Share.png.
Use design/source/Canvas.dc.html for exact sizes, labels and menu contents.

Update the Canvas screen to match:
1. Replace the left rail with the compact version: Insert, Study & math, Writing help,
   Ruler/laser/view, a divider, then Search. Each group button opens a flyout menu to its right.
   Hover (stylus hover or mouse) previews it and closes it on exit. Tap pins it until
   tap-outside, re-tap, or picking an item. Tool items switch the active tool and close it.
   Keep 44dp targets and semantic labels.
2. Top-right pill: a dark filled Share button plus ⋯. Remove the Export button everywhere.
   ⋯ opens a menu with Export, Import, Print, Password protect, Page & paper,
   Version history and Settings. Add the "Export a copy" row to the Share dialog if it exists.
3. Bottom-right: the map card stacked above the zoom pill, both 236dp wide and right-aligned.
   The zoom pill has −, %, +, [show map when hidden], whole board, and full screen. Full screen
   hides every menu except the zoom pill, and tapping it again restores them.
4. Update the widget tests and golden for the new states: default, flyout pinned,
   ⋯ open, map hidden, and full screen.

Plan first, then build it, run flutter analyze and the tests, and commit and push when done.
```
