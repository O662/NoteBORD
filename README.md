# NoteBORD

**Endless** is a handwriting-first notebook app. Each page is paper that grows in any direction as you write. It is built for pens first (Samsung S Pen), with touch for panning and zooming. The design targets Android tablets in landscape (1280×800 dp); phones, Windows, Linux and web come later from the same Flutter codebase.

Progress by phase is in [`docs/PROGRESS.md`](docs/PROGRESS.md).

## What's in the repo

```
lib/                    ← the Flutter app (board model, ink engine, state, UI)
test/                   ← unit, widget and golden tests (goldens at 1280×800)
assets/fonts/           ← Figtree, Newsreader and Caveat, with their OFL licenses
docs/SPEC.md            ← every feature, grouped into build phases
docs/SCREENS.md         ← list of screens and how they link together
docs/BOARD_FORMAT.md    ← the .board file format (export/import and storage)
docs/PROGRESS.md        ← what's done, what's stubbed, what's next
docs/UPDATE_01.md       ← design update 01: canvas chrome cleanup
design/screens/*.png    ← screenshots of every screen (the look to match)
design/source/*.dc.html ← markup behind each screen (exact sizes, colors, copy)
android/, windows/      ← platform projects
```

Kept locally and not committed: `CLAUDE.md` (the brief Claude Code reads), `design/tokens.json` (design tokens) and `tool/` (the token generator). The generated colors in `lib/theme/tokens.g.dart` are committed, so the app builds without them.

## Running it

1. **Install Flutter** (flutter.dev → Get started) and Android Studio, then run `flutter doctor` until everything is green.
2. **Plug in the tablet** with USB debugging on and accept the "Allow USB debugging?" prompt.
3. From the repo root:
   ```
   flutter pub get
   flutter run -d <device id>              # debug, with hot reload (press r)
   flutter run --release -d <device id>    # to judge how the ink really feels
   ```
   `flutter devices` lists device ids. `flutter run -d windows` also works; there the mouse draws and the wheel pans.
4. **Tests:** `flutter analyze` and `flutter test`. After an intended visual change, regenerate goldens with `flutter test --update-goldens test/golden`.

## Working with Claude Code

- Build one phase at a time, in the order in `docs/SPEC.md`. After each phase, run the app on the tablet, try it with the S Pen, and say what feels off. Then say "next phase".
- Commit after each working step, so you can always roll back.

## Tips

- The ink canvas (Phase 1) is the heart of the app: how the pen feels, how fast ink appears, and palm rejection. Everything else sits on top of it.
- Some features need accounts or keys you set up yourself: Google Cloud (Drive and Calendar), Microsoft Entra (OneDrive and Outlook), and possibly MyScript for math.
- If you change the design later, export new screenshots into `design/screens/` and say what changed.
