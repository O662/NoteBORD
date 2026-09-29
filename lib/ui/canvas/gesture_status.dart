import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../canvas/canvas_status.dart';
import '../../canvas/pane.dart';
import '../../state/notebook.dart';
import '../../state/settings.dart';
import '../../theme/colors.dart';
import 'panels.dart';

/// The pen gestures' message for [pane]: a status while the pen is down, or
/// what just happened with an Undo button. Nothing when there's no message.
class GestureStatus extends ConsumerWidget {
  const GestureStatus({super.key, required this.pane, this.orElse});

  final Pane pane;

  /// Shown when there's no message (the Canvas screen's tool hint).
  final Widget? orElse;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ValueListenableBuilder<CanvasStatus?>(
        valueListenable: pane.status,
        builder: (context, status, _) {
          if (status == null) return orElse ?? const SizedBox.shrink();
          final pageId = status.undoPageId;
          if (pageId == null) return HintPill(text: status.text);
          return UndoToast(
            text: status.text,
            onUndo: () {
              ref.read(notebookProvider(pane.notebookId).notifier).undo(pageId);
              pane.status.value = null;
            },
          );
        },
      );
}

/// Laser colors (Tools.dc.html): red, green or blue, under the tool pill
/// while the laser pointer is the tool.
class LaserColors extends ConsumerWidget {
  const LaserColors({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final picked = ref.watch(settingsProvider.select((s) => s.laserColor));
    final options = [('Red laser', c.laserRed), ('Green laser', c.laserGreen), ('Blue laser', c.laserBlue)];
    return Semantics(
      container: true,
      label: 'Laser color',
      explicitChildNodes: true,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: c.line),
          borderRadius: BorderRadius.circular(12),
          boxShadow: c.pillShadow,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, spacing: 2, children: [
          for (final (i, (label, color)) in options.indexed)
            Semantics(
              button: true,
              label: label,
              selected: picked == i,
              excludeSemantics: true,
              child: Material(
                color: picked == i ? c.side : Colors.transparent,
                borderRadius: BorderRadius.circular(9),
                child: InkWell(
                  borderRadius: BorderRadius.circular(9),
                  onTap: () => ref.read(settingsProvider.notifier).apply((s) => s.copyWith(laserColor: i)),
                  child: SizedBox(
                    width: 44,
                    height: 38,
                    child: Center(
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

/// "Line straightened  [Undo]" (Tools.dc.html, Arrows.dc.html, Scribble.dc.html).
class UndoToast extends StatelessWidget {
  const UndoToast({super.key, required this.text, required this.onUndo});

  final String text;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      liveRegion: true,
      explicitChildNodes: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
        decoration: BoxDecoration(
          color: c.inverse,
          borderRadius: BorderRadius.circular(999),
          boxShadow: [BoxShadow(color: c.shadow, offset: const Offset(0, 10), blurRadius: 24, spreadRadius: -12)],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, spacing: 12, children: [
          Text(text, style: TextStyle(fontSize: 14, color: c.onInverse)),
          Semantics(
            button: true,
            label: 'Undo: $text',
            excludeSemantics: true,
            child: Material(
              color: c.inverseRaised,
              borderRadius: BorderRadius.circular(999),
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: onUndo,
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  alignment: Alignment.center,
                  child: Text('Undo', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.onInverse)),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
