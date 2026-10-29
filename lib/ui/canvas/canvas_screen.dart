import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../board/ids.dart';
import '../../canvas/canvas_view.dart';
import '../../canvas/flashcard_mode.dart' show CircledSide;
import '../../board/model.dart' show ChartItem, OfficeItem, StickyItem, TextItem;
import '../../canvas/ink_canvas.dart';
import '../../canvas/pane.dart';
import '../../library/library.dart';
import '../../spelling/dictionary.dart';
import '../../state/notebook.dart';
import '../../state/settings.dart';
import '../../theme/colors.dart';
import '../common.dart';
import '../dialogs.dart';
import '../lock/lock_dialog.dart';
import '../lock/unlock.dart';
import '../math/math_actions.dart';
import '../math/math_bar.dart';
import '../routes.dart';
import '../spell/dictionary_drawer.dart';
import '../spell/spell_mode.dart';
import '../spell/teach_handwriting.dart';
import '../study/flash_actions.dart';
import '../study/flash_widgets.dart';
import '../templates/templates_dialog.dart';
import '../transfer/share_dialog.dart';
import '../transfer/transfer_dialog.dart';
import '../../canvas/selection.dart';
import 'chart_actions.dart';
import 'color_tray.dart';
import 'gesture_status.dart';
import 'insert_actions.dart';
import 'insert_menu.dart';
import 'left_rail.dart';
import 'live_bar.dart';
import 'model_note.dart';
import 'panels.dart';
import 'pen_popover.dart';
import 'top_bar.dart';

export '../math/math_actions.dart' show mathHint;

const toolHints = {
  CanvasTool.pen: 'Tap the pen again for colors and thickness',
  CanvasTool.marker: 'Tap the marker again for colors and thickness',
  CanvasTool.eraser: 'Erase whole strokes · hold the S Pen button to erase from any tool',
  CanvasTool.select: 'Tap anything to select it · drag to move · pinch to resize',
  CanvasTool.lasso: 'Circle ink, shapes or stickies to select them together',
  CanvasTool.laser: 'Laser fades after a second · it’s never saved to the page',
  ...placeHints,
};

const boardHint = 'The whole board · tap anywhere to zoom in there';

const rulerHint = 'Two fingers rotate the ruler · the pen snaps to its edge';


/// What the ⋯ menu items open, until their screens exist.
const _moreFeatures = {
  'Page & paper': 'Page & paper',
  'Version history': 'Version history',
};

/// Handles a ⋯ menu choice for [pane] (shared with Split view).
void handleMoreItem(BuildContext context, Pane pane, MoreItem item, ValueChanged<String> comingSoon) {
  switch (item.label) {
    case 'Settings':
      showQuickSettings(context);
    case 'Password protect':
      showLockDialog(context, pane);
    case 'Export':
      showTransferDialog(context, pane: pane);
    case 'Import':
      showTransferDialog(context, pane: pane, mode: TransferMode.import);
    case 'Print':
      printNotebook(context, pane);
    default:
      comingSoon(_moreFeatures[item.label] ?? item.label);
  }
}

/// Handles a rail menu choice for [pane] (shared with Split view). [hint]
/// shows a tool's hint where the screen has one.
void handleRailItem(
  BuildContext context,
  WidgetRef ref,
  Pane pane,
  RailItem item,
  ValueChanged<String> comingSoon, {
  ValueChanged<String>? hint,
  VoidCallback? onFlashcards,
  VoidCallback? onLive,
}) {
  final settings = ref.read(settingsProvider.notifier);
  void useTool(CanvasTool tool) => settings.apply((s) => s.copyWith(tool: tool));
  switch (item.label) {
    case 'Sticky note':
      runInsert(context, ref, pane, InsertAction.sticky, hint: hint);
    case 'Paper frame':
      runInsert(context, ref, pane, InsertAction.frame, hint: hint);
    case 'Image':
      runInsert(context, ref, pane, InsertAction.image, hint: hint);
    case 'Record audio':
      // Audio comes with a later phase: the same card as in the Insert menu.
      showEntryComingSoon(context, insertSections[1].entries.firstWhere((e) => e.label == 'Audio'));
    case 'Everything else':
      showInsertMenu(context).then((action) {
        if (action != null && context.mounted) {
          runInsert(context, ref, pane, action, hint: hint, onLive: onLive);
        }
      });
    case 'Templates':
      showTemplatesDialog(context, pane: pane);
    case 'Split view':
      openSplitView(context, ref, pane);
    case 'Ruler':
      // Picking it again puts it away.
      if (pane.ruler.visible) {
        pane.ruler.hide();
        return;
      }
      pane.ruler.show(pane.view.size);
      if (!ref.read(settingsProvider).tool.inks) useTool(CanvasTool.pen);
      hint?.call(rulerHint);
    case 'Laser pointer':
      useTool(CanvasTool.laser);
      hint?.call(toolHints[CanvasTool.laser]!);
    case 'Math & graphs':
      startMath(ref, pane);
      hint?.call(mathHint);
    case 'Math tools':
      startMath(ref, pane);
      openMathTools(pane);
    case 'Need to remember' || 'Convert to text':
      // Both start a lasso whose toolbar leads with that action
      // (RememberMark.png, Convert.png). Something already selected gets
      // that toolbar straight away.
      final convert = item.label == 'Convert to text';
      pane.selection.menu = convert ? SelectionMenu.convert : SelectionMenu.remember;
      if (pane.selection.isNotEmpty && ref.read(settingsProvider).tool.selects) return;
      useTool(CanvasTool.lasso);
      hint?.call(convert ? 'Circle the handwriting to convert' : 'Circle what you need to remember');
    default:
      comingSoon(item.feature);
  }
}

/// Picks a tool from the tool pill. Tapping the active pen or marker again
/// calls [onPopover] instead; Select and Lasso lead with Convert to text.
void pickCanvasTool(WidgetRef ref, Pane pane, CanvasTool tool, {required VoidCallback onPopover}) {
  if (ref.read(settingsProvider).tool == tool && tool.inks) {
    onPopover();
    return;
  }
  if (tool.selects) pane.selection.menu = SelectionMenu.convert;
  ref.read(settingsProvider.notifier).apply((s) => s.copyWith(tool: tool));
}

/// Opens Split view with [pane] on the left and, on the right, the most
/// recently edited other notebook (or the next page of this one).
void openSplitView(BuildContext context, WidgetRef ref, Pane pane) {
  final library = ref.read(libraryProvider);
  final other = library.recent(except: pane.notebookId, count: 1).firstOrNull;
  final nb = ref.read(notebookProvider(pane.notebookId));
  final right = other == null
      ? (pane.notebookId, (pane.page + 1) % nb.pages.length)
      : (other.id, other.lastPage);
  context.pushReplacement(Routes.split((pane.notebookId, pane.page), right));
}

/// Renames the notebook shown in [pane].
Future<void> renameNotebook(BuildContext context, WidgetRef ref, String notebookId) async {
  final current = ref.read(libraryProvider).byId(notebookId)?.title ?? '';
  final name = await showNamePrompt(context, title: 'Rename notebook', initial: current, action: 'Rename');
  if (name != null) await ref.read(libraryProvider.notifier).rename(notebookId, name);
}

/// The writing canvas (design/screens/Canvas.png and its Canvas-* states).
class CanvasScreen extends ConsumerStatefulWidget {
  const CanvasScreen({super.key, required this.pane, this.hintDuration = const Duration(seconds: 4)});

  final Pane pane;
  final Duration hintDuration;

  @override
  ConsumerState<CanvasScreen> createState() => _CanvasScreenState();
}

class _CanvasScreenState extends ConsumerState<CanvasScreen> with TickerProviderStateMixin {
  final penLink = LayerLink();
  final markerLink = LayerLink();
  late final AppLifecycleListener _lifecycle;
  bool _popover = false;
  String? _hint;
  Timer? _hintTimer;

  /// Open rail menu, and whether it was pinned by a tap (vs. hover preview).
  String? _fly;
  bool _pinned = false;
  bool _more = false;

  /// Full screen hides every menu except the zoom pill.
  bool _full = false;

  /// The whole board is showing (design/screens/Board.png): everything on
  /// the page at once, no menus. A tap zooms in there.
  bool _board = false;

  /// The zoom and pan to go back to from the whole board.
  (double, Offset)? _before;

  /// Spell check mode (Spell.png), while it's on.
  SpellController? _spell;
  String? _revealed;

  /// The dictionary drawer is open, and the word it was last asked for.
  bool _dict = false;
  String? _lookup;
  int _lookupSerial = 0;

  /// A search match being pointed at, and its highlight fading out.
  Rect? _spot;
  late final AnimationController _spotGlow = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600));

  /// Glides the view to a zoom and place.
  late final AnimationController _glide;
  void Function(double t)? _glideStep;

  Pane get pane => widget.pane;

  @override
  void initState() {
    super.initState();
    _glide = AnimationController(vsync: this, duration: const Duration(milliseconds: 280))
      ..addListener(() => _glideStep?.call(Curves.easeInOutCubic.transform(_glide.value)));
    // Anything unsaved is written as soon as the app leaves the foreground.
    _lifecycle = AppLifecycleListener(onStateChange: (state) {
      if (state == AppLifecycleState.resumed) return;
      // Text still being typed goes on the page first.
      if (state != AppLifecycleState.inactive) pane.dismiss();
      ref.read(notebookProvider(pane.notebookId).notifier).flush();
    });
    pane.addListener(_paneChanged);
    pane.math.addListener(_mathChanged);
    pane.cards.addListener(_cardsChanged);
    pane.panel.addListener(_cardsChanged);
    pane.live.addListener(_cardsChanged);
    pane.selection.addListener(_selectionChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _recordOpened();
      _showSpot();
    });
    _showHint(toolHints[ref.read(settingsProvider).tool]);
  }

  @override
  void dispose() {
    pane.removeListener(_paneChanged);
    pane.math.removeListener(_mathChanged);
    pane.cards.removeListener(_cardsChanged);
    pane.panel.removeListener(_cardsChanged);
    pane.live.removeListener(_cardsChanged);
    pane.selection.removeListener(_selectionChanged);
    _spell?.dispose();
    _lifecycle.dispose();
    _hintTimer?.cancel();
    _glide.dispose();
    _spotGlow.dispose();
    super.dispose();
  }

  /// "Open at this spot": the match in the middle, at a zoom that shows it
  /// whole, highlighted for a moment.
  void _showSpot() {
    final spot = pane.spot;
    if (spot == null || !mounted) return;
    pane.spot = null;
    final turn = pane.spotTurn;
    pane.spotTurn = null;
    if (turn != null) {
      // The match is on another slide: show it (not an undo step).
      final nb = ref.read(notebookProvider(pane.notebookId));
      final page = nb.pageAt(pane.page);
      final notebook = ref.read(notebookProvider(pane.notebookId).notifier);
      switch (page[turn.$1]) {
        case OfficeItem card when card.page != turn.$2 && turn.$2 >= 1 && turn.$2 <= card.pages:
          notebook.setQuietly(page.id, card.copyWith(page: turn.$2));
        case StickyItem stack when turn.$2 >= 1 && turn.$2 < stack.count:
          // The note it's on comes to the top (as Next note would bring it).
          notebook.setQuietly(page.id, stack.broughtToTop(turn.$2));
        default:
          break;
      }
    }
    final view = pane.view;
    if (view.size.isEmpty) return;
    var scale = view.scale;
    final room = view.size.width * 0.6;
    if (spot.width * scale > room) scale = (room / spot.width).clamp(CanvasView.minScale, 1.0);
    view.jumpTo(scale, view.size.center(Offset.zero) - spot.center * scale);
    setState(() => _spot = spot);
    _spotGlow.forward(from: 0).whenCompleteOrCancel(() {
      if (mounted) setState(() => _spot = null);
    });
  }

  void _paneChanged() {
    setState(() {});
    _recordOpened();
  }

  void _recordOpened() {
    if (mounted) ref.read(libraryProvider.notifier).recordOpened(pane.notebookId, pane.page);
  }

  void _showHint(String? text) {
    _hintTimer?.cancel();
    setState(() => _hint = text);
    if (text != null) _hintTimer = Timer(widget.hintDuration, () => setState(() => _hint = null));
  }

  void _comingSoon(String feature) {
    _hintTimer?.cancel();
    setState(() => _hint = null);
    showComingSoon(context, feature);
  }

  void _closeMenus() => setState(() {
        _fly = null;
        _pinned = false;
        _more = false;
      });

  void _pickTool(CanvasTool tool) {
    var toggled = false;
    pickCanvasTool(ref, pane, tool, onPopover: () => toggled = true);
    if (toggled) {
      setState(() => _popover = !_popover);
      return;
    }
    setState(() => _popover = false);
    _showHint(toolHints[tool]);
  }

  void _togglePopover() {
    final settings = ref.read(settingsProvider.notifier);
    if (!ref.read(settingsProvider).tool.inks) {
      settings.apply((s) => s.copyWith(tool: CanvasTool.pen));
    }
    setState(() => _popover = !_popover);
  }

  void _toggleTray() {
    ref.read(settingsProvider.notifier).apply((s) => s.copyWith(trayOpen: !s.trayOpen));
    setState(() => _popover = false);
  }

  // Rail menus: hover previews, tap pins.
  void _hoverGroup(String id) {
    if (!_pinned) setState(() => _fly = id);
    if (_more) setState(() => _more = false);
  }

  void _tapGroup(String id) => setState(() {
        if (_pinned && _fly == id) {
          _fly = null;
          _pinned = false;
        } else {
          _fly = id;
          _pinned = true;
          _more = false;
          _popover = false;
        }
      });

  void _leaveRail() {
    if (!_pinned && _fly != null) setState(() => _fly = null);
  }

  void _pickRailItem(RailItem item) {
    _closeMenus();
    switch (item.label) {
      case 'Math & graphs':
        _startMath();
      case 'Math tools':
        // The Math tools bar (MathKit.png), with the keyboard's symbols.
        _startMath();
        _openSymbols();
      case 'Make flashcards':
        _startFlashcards();
      case 'Spell check':
        _startSpell();
      case 'Dictionary & thesaurus':
        _openDictionary();
      default:
        handleRailItem(context, ref, pane, item, _comingSoon, hint: _showHint, onFlashcards: _startFlashcards, onLive: _startLive);
    }
  }

  // Live items (LiveItems.png) and charts (Charts.png).

  /// The Live items bar in place of the tool pill: a clock, the date, a
  /// time stamp or a checklist where there's room. The pen keeps writing.
  void _startLive() {
    _endSpell();
    if (pane.cards.on) endFlashcards(ref, pane);
    if (pane.math.on) endMath(ref, pane);
    ref.read(settingsProvider.notifier).apply((s) => s.tool.inks ? s : s.copyWith(tool: CanvasTool.pen));
    pane.live.start();
    setState(() {
      _popover = false;
      _dict = false;
    });
    _showHint(liveHint);
  }

  void _endLive() {
    pane.live.end();
    _showHint(toolHints[ref.read(settingsProvider).tool]);
  }

  /// The chart selected on its own, for the Chart selected bar.
  String? _chartId;

  ChartItem? _selectedChart() {
    final ids = pane.selection.ids;
    if (ids.length != 1) return null;
    final item = ref.read(notebookProvider(pane.notebookId)).pageAt(pane.page)[ids.single];
    return item is ChartItem ? item : null;
  }

  void _selectionChanged() {
    final id = _selectedChart()?.id;
    if (id != _chartId && mounted) setState(() => _chartId = id);
  }

  /// Done on the Chart selected bar: back to writing.
  void _chartDone() {
    pane.selection.clear();
    ref.read(settingsProvider.notifier).apply((s) => s.copyWith(tool: CanvasTool.pen));
  }

  // Making flashcards (FlashMake.png).

  void _startFlashcards([CircledSide? front]) {
    _endSpell();
    pane.live.end();
    startFlashcards(ref, pane, front: front);
    setState(() {
      _popover = false;
      _dict = false;
    });
    _hintTimer?.cancel();
    _hint = null;
  }

  void _endFlashcards() {
    endFlashcards(ref, pane);
    _showHint(toolHints[CanvasTool.pen]);
  }

  void _cardsChanged() {
    if (mounted) setState(() {});
  }

  void _addCard() => addCard(ref, pane);

  /// The dictionary's Make flashcard: the word on the front, its meaning on
  /// the back, into the deck used last.
  void _wordCard(DictEntry entry, DictSense sense) {
    final card = addTextCard(
      ref,
      pane,
      front: entry.word,
      back: '${sense.wordClass.label} · ${sentence(sense.definition)}',
    );
    if (card == null) return;
    final page = ref.read(notebookProvider(pane.notebookId)).pageAt(pane.page);
    pane.toast(
      'Card added to ${card.deckName}',
      undoPageId: page.id,
      action: ('Study now', () => context.push(Routes.flashcards(card.deck))),
    );
  }

  // Math mode (Math.png, MathKit.png).

  void _startMath() {
    _endSpell();
    pane.live.end();
    if (pane.cards.on) endFlashcards(ref, pane);
    startMath(ref, pane);
    setState(() {
      _popover = false;
      _dict = false;
    });
    _showHint(mathHint);
  }

  void _endMath() {
    endMath(ref, pane);
    _showHint(toolHints[CanvasTool.pen]);
  }

  /// Lasso in the math bar picks the lasso tool (and back to the pen). Math
  /// mode started from the Insert menu closes what it would cover.
  void _mathChanged() {
    final mode = pane.math;
    if (mode.on) {
      if (followMathTool(ref, pane)) {
        _showHint(mode.lasso ? 'Circle the math to convert, graph or copy' : (mode.select ? mathSelectHint : mathHint));
      }
      _dict = false;
      _popover = false;
    }
    if (mounted) setState(() {});
  }

  /// Formulas & tools: the Math tools bar, with the keyboard on Symbols.
  void _openSymbols() => openMathTools(pane);

  /// Math tools' Done: back to math mode's own bar.
  void _closeTools() {
    closeMathTools(pane);
    _showHint(mathHint);
  }

  // Spell check and the dictionary (Spell.png).

  /// Where the suggestion card sits: 100 in from the left, 136 up from the
  /// bottom (Spell.dc.html), as wide as fits beside the dictionary.
  static const _cardLeft = 100.0, _cardBottom = 136.0, _cardHeight = 200.0;

  double get _drawerReach => _dict ? 14 + DictionaryDrawer.width + 16 : 16;

  void _startSpell() {
    if (_spell != null) return;
    if (pane.math.on) pane.math.end();
    pane.live.end();
    if (pane.cards.on) endFlashcards(ref, pane);
    pane
      ..dismiss()
      ..selection.clear();
    _hintTimer?.cancel();
    setState(() {
      _hint = null;
      _popover = false;
      _spell = SpellController(ref, pane)..addListener(_spellChanged);
      _revealed = null;
    });
  }

  void _endSpell() {
    final spell = _spell;
    if (spell == null) return;
    setState(() {
      _spell = null;
      _dict = false;
    });
    spell
      ..removeListener(_spellChanged)
      ..dispose();
    _showHint(toolHints[ref.read(settingsProvider).tool]);
  }

  /// The card's word changed: bring it into view, clear of the card and
  /// the dictionary.
  void _spellChanged() {
    final issue = _spell?.current;
    if (issue == null || issue.id == _revealed || !mounted) return;
    _revealed = issue.id;
    final view = pane.view;
    final size = view.size;
    if (size.isEmpty) return;
    final clear = Rect.fromLTRB(_cardLeft, 96, size.width - _drawerReach, size.height - _cardBottom - _cardHeight - 16);
    if (clear.width <= 0 || clear.height <= 0) return;
    final r = Rect.fromPoints(view.toScreen(issue.rect.topLeft), view.toScreen(issue.rect.bottomRight));
    final dx = r.left >= clear.left && r.right <= clear.right ? 0.0 : clear.center.dx - r.center.dx;
    final dy = r.top >= clear.top && r.bottom <= clear.bottom ? 0.0 : clear.top + clear.height * 0.4 - r.center.dy;
    if (dx != 0 || dy != 0) _glideTo(view.scale, view.translation + Offset(dx, dy));
  }

  /// A tap on the page in spell check: an underlined word becomes the one
  /// the card is about.
  void _spellTap(Offset at) {
    final spell = _spell;
    if (spell == null) return;
    final reach = 8 / pane.view.scale;
    for (final issue in spell.issues) {
      if (issue.rect.inflate(reach).contains(at)) {
        spell.select(issue.id);
        return;
      }
    }
  }

  void _openDictionary([String? word]) => setState(() {
        _dict = true;
        _lookup = word;
        _lookupSerial++;
      });

  /// "Add definition to page": a text box in the middle of what's showing.
  void _addDefinition(DictEntry entry, DictSense sense) {
    final nb = ref.read(notebookProvider(pane.notebookId));
    final page = nb.pageAt(pane.page);
    if (nb.isSealed(page.id)) return;
    final view = pane.view;
    final size = view.size;
    final left = _spell != null ? _cardLeft : 80.0;
    final bottom = _spell != null ? size.height - _cardBottom - _cardHeight : size.height - 16;
    final mid = view.toPage(Offset((left + size.width - _drawerReach) / 2, (84 + bottom) / 2));
    final now = DateTime.now().toUtc();
    final text = TextItem(
      id: newId('it', now: now),
      x: 0,
      y: 0,
      z: page.nextZ,
      createdAt: now,
      wrap: 420,
      text: '${entry.word} · ${sense.wordClass.label}\n${sentence(sense.definition)}',
      size: 20,
      color: ref.read(settingsProvider).penColor,
    );
    ref.read(notebookProvider(pane.notebookId).notifier).insertItems(page.id, [
      text.copyWith(x: mid.dx - text.w / 2, y: mid.dy - text.h / 2),
    ]);
    pane.toast('Added the definition of “${entry.word}” to the page', undoPageId: page.id);
  }

  void _toggleMore() => setState(() {
        _more = !_more;
        _fly = null;
        _pinned = false;
        _popover = false;
      });

  void _pickMoreItem(MoreItem item) {
    _closeMenus();
    handleMoreItem(context, pane, item, _comingSoon);
  }

  void _toggleFull() => setState(() {
        _full = !_full;
        _fly = null;
        _pinned = false;
        _more = false;
        _popover = false;
      });

  void _setMap(bool open) {
    if (open && _full) setState(() => _full = false);
    ref.read(settingsProvider.notifier).apply((s) => s.copyWith(mapOpen: open));
  }

  /// Glides from the current zoom and pan to [scale] and [translation].
  void _glideTo(double scale, Offset translation) {
    final view = pane.view;
    final mid = view.size.center(Offset.zero);
    final s0 = view.scale;
    final c0 = view.toPage(mid), c1 = (mid - translation) / scale;
    _glideStep = (t) {
      final s = s0 * math.pow(scale / s0, t);
      view.jumpTo(s, mid - Offset.lerp(c0, c1, t)! * s);
    };
    _glide
      ..stop()
      ..value = 0
      ..forward();
  }

  /// The zoom pill's "whole board" button: everything on the page at once,
  /// or back to where you were.
  void _toggleBoard() {
    if (_board) {
      _leaveBoard();
      return;
    }
    final content = ref.read(notebookProvider(pane.notebookId)).pageAt(pane.page).contentBounds;
    final view = pane.view;
    if (content == null) {
      view.reset();
      _showHint('Nothing on this page yet');
      return;
    }
    _before = (view.scale, view.translation);
    pane
      ..dismiss()
      ..selection.clear();
    setState(() {
      _board = true;
      _fly = null;
      _pinned = false;
      _more = false;
      _popover = false;
    });
    final size = view.size;
    // The menus are hidden, so the board gets the whole screen (Board.png).
    final fit = view.fitted(content.inflate(32), Rect.fromLTRB(36, 56, size.width - 36, size.height - 72));
    if (fit != null) _glideTo(fit.$1, fit.$2);
    _showHint(boardHint);
  }

  /// Leaves the whole board: back to the zoom you had, at the same place
  /// or, after a tap, centered [at] that page point.
  void _leaveBoard({Offset? at}) {
    if (!_board) return;
    final view = pane.view;
    final (scale, translation) = _before ?? (1.0, view.home);
    setState(() => _board = false);
    _glideTo(scale, at == null ? translation : view.size.center(Offset.zero) - at * scale);
    _showHint(toolHints[ref.read(settingsProvider).tool]);
  }

  void _back() => leaveNotebook(context);

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final nb = ref.watch(notebookProvider(pane.notebookId));
    final notebook = ref.read(notebookProvider(pane.notebookId).notifier);
    final pageId = nb.pageAt(pane.page).id;
    final sealed = nb.isSealed(pageId);
    if (sealed && _board) _board = false;
    if (sealed && _spell != null) WidgetsBinding.instance.addPostFrameCallback((_) => _endSpell());
    final spelling = _spell != null && !sealed;
    final mode = pane.math;
    final mathOn = mode.on && !sealed;
    final cardsOn = pane.cards.on && !sealed;
    final liveOn = pane.live.on && !sealed;
    final chrome = !_full && !_board;
    final tools = chrome && !sealed && !spelling && !mathOn && !cardsOn && !liveOn;
    final chart = tools ? _selectedChart() : null;
    // The dictionary drawer covers the pages rail, the map and the zoom pill;
    // math mode and making flashcards have neither (Math.png, FlashMake.png),
    // and Remember this takes their place (RememberMark.png).
    final panel = pane.panel.value && !sealed;
    final right = !spelling && !_dict && !mathOn && !cardsOn && !liveOn && !panel;
    final mapShown = tools && right && settings.mapOpen;
    final blocking = tools && (_more || (_pinned && _fly != null));
    // The math keyboard is where the hint would be.
    final hintShown = !sealed && _hint != null && !_popover && !blocking && pane.math.draft == null;

    return Scaffold(
      body: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyZ, control: true): () => notebook.undo(pageId),
          const SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true): () => notebook.redo(pageId),
          const SingleActivator(LogicalKeyboardKey.keyY, control: true): () => notebook.redo(pageId),
          const SingleActivator(LogicalKeyboardKey.escape): () {
            if (_spell != null) return _endSpell();
            if (pane.cards.on) return _endFlashcards();
            if (pane.math.draft != null) return pane.math.closeKeyboard();
            if (pane.math.tools) return _closeTools();
            if (pane.math.on) return _endMath();
            if (pane.live.on) return _endLive();
            _closeMenus();
            pane
              ..dismiss()
              ..selection.clear();
            _leaveBoard();
            setState(() => _popover = false);
          },
        },
        child: Focus(
          autofocus: true,
          child: Stack(children: [
            Positioned.fill(
              child: Listener(
                onPointerDown: (_) {
                  if (_popover) setState(() => _popover = false);
                  _glide.stop(); // a touch takes over from a glide
                },
                child: InkCanvas(
                  pane: pane,
                  onViewTap: _board ? (at) => _leaveBoard(at: at) : (spelling ? _spellTap : null),
                  onFlashcards: _startFlashcards,
                  // Clear of the rail, the top pills (and the color tray), and the pages rail.
                  chrome: EdgeInsets.fromLTRB(
                    80,
                    tools && (settings.trayOpen || settings.tool == CanvasTool.laser || settings.tool == CanvasTool.shape)
                        ? 128
                        : 84,
                    _dict ? _drawerReach : (chrome && settings.pagesOpen && !mathOn && !panel ? 124 : 60),
                    16,
                  ),
                ),
              ),
            ),
            if (_spot != null && !sealed)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(painter: SpotPainter(pane.view, _spot!, _spotGlow, context.colors)),
                ),
              ),
            if (spelling)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(painter: SpellMarksPainter(pane.view, _spell!, context.colors)),
                ),
              ),
            if (sealed)
              Positioned.fill(
                child: LockedOverlay(
                  notebookId: pane.notebookId,
                  pageId: pageId,
                  pageNumber: pane.page + 1,
                  onBack: _back,
                ),
              ),
            SafeArea(
              child: LayoutBuilder(builder: (context, box) {
                return Stack(clipBehavior: Clip.none, children: [
                  if (chrome)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: 72,
                      child: TopBar(
                        title: TitlePill(
                          pane: pane,
                          onBack: _back,
                          onRename: () => renameNotebook(context, ref, pane.notebookId),
                        ),
                        pane: pane,
                        showTools: tools,
                        showActions: tools,
                        popoverOpen: _popover,
                        penLink: penLink,
                        markerLink: markerLink,
                        onPickTool: _pickTool,
                        onTogglePopover: _togglePopover,
                        onToggleTray: _toggleTray,
                        moreOpen: _more,
                        onToggleMore: _toggleMore,
                        onShare: () => showShareDialog(context, pane),
                        center: spelling
                            ? SpellBar(spell: _spell!, onDone: _endSpell)
                            : cardsOn
                                ? FlashBar(pane: pane, compact: box.maxWidth < 1100, onDone: _endFlashcards)
                                : mathOn
                                ? MathBar(
                                    math: mode,
                                    compact: box.maxWidth < 1100,
                                    onFormulas: _openSymbols,
                                    onAddGraph: () => addGraph(pane),
                                    onDone: _endMath,
                                    onTool: mode.addTool,
                                    onToolsDone: _closeTools,
                                  )
                                : liveOn
                                ? LiveBar(onAdd: pane.live.add, onDone: _endLive)
                                : chart != null
                                ? ChartBar(
                                    linked: chart.linked,
                                    onChangeData: () => editChartData(context, ref, pane, chart),
                                    onColors: () => editChartColors(context, ref, pane, chart),
                                    onUnlink: () => unlinkChart(ref, pane, chart),
                                    onLinkAgain: canLinkAgain(nb.pageAt(pane.page), chart) ? () => linkChartAgain(ref, pane, chart) : null,
                                    onDone: _chartDone,
                                  )
                                : null,
                      ),
                    ),
                  if (tools && settings.tool == CanvasTool.laser && !_popover)
                    const Positioned(top: 74, left: 0, right: 0, child: Center(child: LaserColors()))
                  else if (tools && settings.tool == CanvasTool.shape && !_popover)
                    const Positioned(top: 74, left: 0, right: 0, child: Center(child: ShapeKinds()))
                  else if (tools && settings.trayOpen && !_popover)
                    const Positioned(top: 70, left: 0, right: 0, child: Center(child: ColorTray())),
                  if (chrome && right)
                    Positioned(
                      right: settings.pagesOpen ? 14 : 0,
                      top: 84,
                      // Never below zero: the on-screen keyboard can take most of the height.
                      child: PagesRail(pane: pane, maxHeight: math.max(0, box.maxHeight - 84 - (mapShown ? 250 : 80))),
                    ),
                  if (cardsOn && chrome) ...[
                    Positioned(
                      top: 84,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: FlashHint(
                          mode: pane.cards,
                          onStudy: () => context.push(Routes.flashcards(pane.cards.deckId)),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 42,
                      child: Center(child: NewCardPanel(pane: pane, onAdd: _addCard)),
                    ),
                  ],
                  if (!sealed && !blocking && !cardsOn)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 20,
                      child: Center(
                        child: GestureStatus(pane: pane, orElse: hintShown ? HintPill(text: _hint!) : null),
                      ),
                    ),
                  if (!sealed && right)
                    Positioned(
                      right: 14,
                      bottom: 16,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.end, spacing: 8, children: [
                        if (mapShown) MapPanel(pane: pane, onHide: () => _setMap(false)),
                        ZoomPill(
                          view: pane.view,
                          onFit: _toggleBoard,
                          board: _board,
                          showMapButton: !mapShown && !_board,
                          onShowMap: () => _setMap(true),
                          fullScreen: _full,
                          onToggleFullScreen: _toggleFull,
                        ),
                      ]),
                    ),
                  if (spelling)
                    Positioned(
                      left: _cardLeft,
                      bottom: _cardBottom,
                      child: SpellCard(
                        spell: _spell!,
                        width: math.min(720, box.maxWidth - _cardLeft - _drawerReach),
                        onLookUp: _openDictionary,
                        onTeach: () => showTeachHandwriting(context),
                      ),
                    ),
                  if (_dict && !sealed)
                    Positioned(
                      right: 14,
                      top: 84,
                      bottom: 16,
                      child: DictionaryDrawer(
                        query: _lookup,
                        serial: _lookupSerial,
                        onClose: () => setState(() => _dict = false),
                        onAddDefinition: _addDefinition,
                        onFlashcard: _wordCard,
                      ),
                    ),
                  // The handwriting model downloading on first use.
                  if (!sealed && chrome) const Positioned(left: 14, bottom: 16, child: ModelNoteView()),
                  // A pinned menu or ⋯ stays open until a tap anywhere else.
                  if (blocking)
                    Positioned.fill(
                      child: Listener(behavior: HitTestBehavior.opaque, onPointerDown: (_) => _closeMenus()),
                    ),
                  if (tools)
                    Positioned(
                      left: 12,
                      top: 84,
                      child: LeftRail(
                        openId: _fly,
                        pinned: _pinned,
                        onHover: _hoverGroup,
                        onTap: _tapGroup,
                        onLeave: _leaveRail,
                        onClose: _closeMenus,
                        onItem: _pickRailItem,
                        onSearch: () {
                          _closeMenus();
                          context.push(Routes.search());
                        },
                      ),
                    ),
                  if (tools && _more) Positioned(right: 12, top: 70, child: MoreMenu(onItem: _pickMoreItem)),
                  if (tools && _popover)
                    Positioned(
                      left: 0,
                      top: 0,
                      child: CompositedTransformFollower(
                        link: settings.tool == CanvasTool.marker ? markerLink : penLink,
                        showWhenUnlinked: false,
                        targetAnchor: Alignment.bottomCenter,
                        offset: const Offset(-51, 13),
                        child: PenPopover(
                          caretLeft: 45,
                          onClose: () => setState(() => _popover = false),
                          onComingSoon: _comingSoon,
                        ),
                      ),
                    ),
                ]);
              }),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Highlights a search match on the page ("Open at this spot"), then fades.
class SpotPainter extends CustomPainter {
  SpotPainter(this.view, this.spot, this.glow, this.colors) : super(repaint: Listenable.merge([view, glow]));

  final CanvasView view;
  final Rect spot;
  final Animation<double> glow;
  final EndlessColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    final t = glow.value;
    final fade = t < 0.7 ? 1.0 : (1 - t) / 0.3;
    if (fade <= 0) return;
    final r = Rect.fromPoints(view.toScreen(spot.topLeft), view.toScreen(spot.bottomRight)).inflate(6);
    final box = RRect.fromRectAndRadius(r, const Radius.circular(10));
    canvas.drawRRect(box, Paint()..color = colors.searchHit.withValues(alpha: colors.searchHit.a * fade * 0.8));
    canvas.drawRRect(
      box,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = colors.accent.withValues(alpha: fade),
    );
  }

  @override
  bool shouldRepaint(SpotPainter old) => old.spot != spot || old.colors != colors;
}
