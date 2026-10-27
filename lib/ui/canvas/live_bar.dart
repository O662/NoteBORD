import 'package:flutter/material.dart';

import '../../canvas/live_mode.dart';
import '../../theme/colors.dart';
import '../../theme/tokens.g.dart';
import '../icons.dart';
import '../math/math_bar.dart' show MathBarButton;

// The dark bars in place of the tool pill for live items and charts
// (LiveItems.dc.html's and Charts.dc.html's toolbars).

/// The hint while the Live items bar is up (LiveItems.png's status).
const liveHint = 'Clocks, dates and “time ago” stamps update by themselves · stamps keep the moment they were made';

class _DarkBar extends StatelessWidget {
  const _DarkBar({required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      container: true,
      label: label,
      explicitChildNodes: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
        decoration: BoxDecoration(
          color: c.inverse,
          borderRadius: BorderRadius.circular(Radii.pill),
          boxShadow: c.pillShadow,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: children),
      ),
    );
  }
}

/// "Live items · Clock · Today's date · Stamp time · Checklist · Done".
class LiveBar extends StatelessWidget {
  const LiveBar({super.key, required this.onAdd, required this.onDone});

  final ValueChanged<LiveKind> onAdd;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return _DarkBar(label: 'Live items', children: [
      Padding(
        padding: const EdgeInsets.only(right: 4),
        child: Text('Live items', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.onInverse)),
      ),
      MathBarButton(label: 'Clock', tight: true, onTap: () => onAdd(LiveKind.clock)),
      MathBarButton(label: 'Today’s date', tight: true, onTap: () => onAdd(LiveKind.date)),
      // The one that's used most, in plum like the stamps.
      Semantics(
        button: true,
        label: 'Stamp time',
        excludeSemantics: true,
        child: Material(
          color: c.plumBright,
          borderRadius: BorderRadius.circular(Radii.button),
          child: InkWell(
            borderRadius: BorderRadius.circular(Radii.button),
            onTap: () => onAdd(LiveKind.stamp),
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
                EIcon(EIcons.stamp, size: 14, color: c.onPlumBright),
                Text('Stamp time', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.onPlumBright)),
              ]),
            ),
          ),
        ),
      ),
      MathBarButton(label: 'Checklist', tight: true, onTap: () => onAdd(LiveKind.checklist)),
      MathBarButton(label: 'Done', done: true, onTap: onDone),
    ]);
  }
}

/// "Chart selected · Change data · Colors · Unlink (snapshot) · Done", with
/// Link again in place of Unlink for a chart that was unlinked.
class ChartBar extends StatelessWidget {
  const ChartBar({
    super.key,
    required this.linked,
    required this.onChangeData,
    required this.onColors,
    required this.onUnlink,
    required this.onLinkAgain,
    required this.onDone,
  });

  final bool linked;
  final VoidCallback onChangeData;
  final VoidCallback onColors;
  final VoidCallback onUnlink;

  /// Null when its table or sheet isn't on the page any more.
  final VoidCallback? onLinkAgain;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return _DarkBar(label: 'Chart tools', children: [
      EIcon(EIcons.chart, size: 18, color: c.onInverse),
      Padding(
        padding: const EdgeInsets.only(left: 2, right: 2),
        child: Text('Chart selected', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.onInverse)),
      ),
      MathBarButton(label: 'Change data', tight: true, onTap: onChangeData),
      MathBarButton(label: 'Colors', tight: true, onTap: onColors),
      if (linked)
        MathBarButton(label: 'Unlink (snapshot)', tight: true, onTap: onUnlink)
      else if (onLinkAgain case final link?)
        MathBarButton(label: 'Link again', tight: true, onTap: link),
      MathBarButton(label: 'Done', done: true, onTap: onDone),
    ]);
  }
}
