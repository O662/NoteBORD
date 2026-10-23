import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../canvas/math_mode.dart';
import '../../canvas/pane.dart';
import '../../state/settings.dart';
import 'math_keys.dart' show symbolsTab;

// Math mode's steps, shared by the Canvas screen, Split view and the Insert
// menu: start and end it, Add a graph, the Math tools bar, and Esc.

const mathHint = 'Write math with the pen and pause · tap with a finger to type it';

/// Math mode in [pane]: the pen writes math (the marker and the other tools
/// give way to it).
void startMath(WidgetRef ref, Pane pane) {
  pane
    ..dismiss()
    ..selection.clear();
  pane.math.start();
  final tool = ref.read(settingsProvider).tool;
  if (!tool.inks || tool == CanvasTool.marker) {
    ref.read(settingsProvider.notifier).apply((s) => s.copyWith(tool: CanvasTool.pen));
  }
}

/// Leaves math mode (Done), back to the pen.
void endMath(WidgetRef ref, Pane pane) {
  pane.math.end();
  ref.read(settingsProvider.notifier).apply((s) => s.copyWith(tool: CanvasTool.pen));
}

/// The math bar's Lasso picks the lasso tool, and back to the pen. True
/// when the tool changed.
bool followMathLasso(WidgetRef ref, Pane pane) {
  final mode = pane.math;
  if (!mode.on) return false;
  final want = mode.lasso ? CanvasTool.lasso : CanvasTool.pen;
  final tool = ref.read(settingsProvider).tool;
  if (tool == want || (tool != CanvasTool.pen && tool != CanvasTool.lasso)) return false;
  ref.read(settingsProvider.notifier).apply((s) => s.copyWith(tool: want));
  return true;
}

/// Where new math typed from the bar goes: up and left of the middle of
/// [pane], clear of the keyboard.
Offset typingSpot(Pane pane) {
  final view = pane.view;
  return view.toPage(Offset(view.size.width * 0.25, view.size.height * 0.3));
}

/// Add a graph: the keyboard types the function, and Insert graphs it.
void addGraph(Pane pane) {
  pane.math
    ..type(MathDraft(at: typingSpot(pane), text: 'y = ', purpose: DraftFor.newGraph))
    ..tab = 0;
}

/// Formulas & tools: the Math tools bar, and the keyboard on its Symbols tab
/// (opened for new math if it isn't open).
void openMathTools(Pane pane) {
  final mode = pane.math;
  if (mode.draft == null) mode.type(MathDraft(at: typingSpot(pane)));
  mode
    ..tab = symbolsTab
    ..tools = true;
}

/// Math tools' Done: back to math mode's own bar.
void closeMathTools(Pane pane) {
  pane.math
    ..closeKeyboard()
    ..tools = false;
}

/// Esc in math mode: the keyboard closes, then Math tools, then math mode.
/// False when math mode isn't on and the keyboard is closed.
bool escapeMath(WidgetRef ref, Pane pane) {
  final mode = pane.math;
  if (mode.draft != null) {
    mode.closeKeyboard();
    return true;
  }
  if (mode.tools) {
    closeMathTools(pane);
    return true;
  }
  if (mode.on) {
    endMath(ref, pane);
    return true;
  }
  return false;
}
