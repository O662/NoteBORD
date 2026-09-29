# Screens

Each screen is 1280×800 (Android tablet, landscape). The PNG is in `design/screens/`, and the markup and sample data are in `design/source/`.

## Core flow — tablet, landscape

| Screen | What it shows |
|---|---|
| `Start` | Start page |
| `Main` | Library + folders |
| `Canvas` | Writing canvas (S Pen) |
| `Split` | Split view |
| `Search` | Handwriting search |

## Files & sync

| Screen | What it shows |
|---|---|
| `Export` | Import / export |
| `Sync` | Cloud sync settings |

## Canvas tools & assets

| Screen | What it shows |
|---|---|
| `Insert` | Insert menu (assets) |
| `Board` | Whole board: frames, stickies, embeds |
| `Tools` | Hold to straighten, ruler, laser |
| `Templates` | Templates |
| `Lock` | Password protection |

## Handwriting, sharing & live collaboration

| Screen | What it shows |
|---|---|
| `Convert` | Handwriting to text |
| `Scribble` | Scribble to erase |
| `Share` | Share |
| `Live` | Live collaboration |

## Plan & study

| Screen | What it shows |
|---|---|
| `Calendar` | Calendar (Google + Outlook) |
| `Planner` | Planner: today, 3 days, week |
| `WidgetBoard` | Calendar, planner & flashcard widgets on a page |
| `FlashMake` | Make flashcards by circling |
| `Study` | Study flashcards |

## Need to remember

| Screen | What it shows |
|---|---|
| `RememberMark` | Mark something to remember |
| `Remember` | Need to remember |

## Math, graphs, charts & arrows

| Screen | What it shows |
|---|---|
| `Math` | Math equations + Greek symbols |
| `Graph` | Graphs: 2D (x y) and 3D (x y z) |
| `Arrows` | Flick back to make an arrow |
| `Charts` | Chart widgets linked to tables & Excel |

## Themes & dark mode

| Screen | What it shows |
|---|---|
| `Themes` | Themes & dark mode settings |
| `CanvasDark` | Writing canvas in dark mode |

## Audio & video

| Screen | What it shows |
|---|---|
| `Audio` | Record audio, replay with ink, transcript |
| `Video` | Videos in notes |

## Spell check, live items & math tools

| Screen | What it shows |
|---|---|
| `Spell` | Spell check + dictionary & thesaurus |
| `LiveItems` | Live clock, date, time stamps, checklists |
| `MathKit` | Number line, unit circle, polar, formulas & symbols |

## How the screens connect
- Start: New note → Canvas. Continue writing → Canvas. Sidebar → Library (Main), Calendar, Flashcards (Study), Remember.
- Canvas top-right: Share (dialog includes Export a copy) and ⋯ (Export, Import, Print, Password protect, Page & paper, Version history, Settings).
- Canvas left rail: Insert menu, Study & math menu (RememberMark, FlashMake, Math, MathKit), Writing help menu (Spell, Convert), Ruler/laser/view menu (Tools, Split), and Search.
- Extra Canvas states: `Canvas-rail-hover-insert`, `Canvas-rail-pinned`, `Canvas-more-menu`, `Canvas-map-hidden`, `Canvas-fullscreen`.
- Insert menu: Math, Graph, Video, Audio, Charts, WidgetBoard, LiveItems.
- Math → Formulas & tools (MathKit), and Add a graph (Graph).
- Settings: Sync, then Themes & dark mode.
