import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../theme/colors.dart';
import '../../theme/tokens.g.dart';
import '../icons.dart';
import '../routes.dart';

// Parts shared by the Calendar and Planner screens (Calendar.dc.html,
// Planner.dc.html): the dark Calendar · Planner switch, the light
// segmented choice (Day · Week · Month, Today · 3 days · Week), the title,
// and the cards everything sits in.

/// Calendar · Planner, in a dark pill.
class CalendarPlannerSwitch extends StatelessWidget {
  const CalendarPlannerSwitch({super.key, required this.planner});

  final bool planner;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget item(String label, bool on, String to) => Semantics(
      button: true,
      selected: on,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: on ? c.surface : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: on ? null : () => context.go(to),
          child: Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(fontSize: 14, fontWeight: on ? FontWeight.w700 : FontWeight.w600, color: on ? c.text : c.onInverse),
            ),
          ),
        ),
      ),
    );
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: c.inverse, borderRadius: BorderRadius.circular(12)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 2,
        children: [item('Calendar', !planner, Routes.calendar), item('Planner', planner, Routes.planner)],
      ),
    );
  }
}

/// One of a few choices, on a light pill (the view, the plan's range).
class Segmented<T> extends StatelessWidget {
  const Segmented({
    super.key,
    required this.values,
    required this.labels,
    required this.value,
    required this.onChanged,
    required this.label,
    this.height = 38,
    this.padding = 12,
    this.fontSize = 14,
    this.radius = 12,
    this.dark = false,
  });

  final List<T> values;
  final List<String> labels;
  final T value;
  final ValueChanged<T> onChanged;

  /// For screen readers ("View").
  final String label;
  final double height;
  final double padding;
  final double fontSize;
  final double radius;

  /// On the dark toolbar (WidgetBoard.dc.html's widget options).
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final inner = radius - 3;
    return Semantics(
      container: true,
      label: label,
      explicitChildNodes: true,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: dark ? c.inverse : c.side, borderRadius: BorderRadius.circular(radius)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 2,
          children: [
            for (final (i, v) in values.indexed)
              Semantics(
                button: true,
                inMutuallyExclusiveGroup: true,
                selected: v == value,
                label: labels[i],
                excludeSemantics: true,
                child: Material(
                  color: v == value ? (dark ? c.inverseRaised : c.surface) : Colors.transparent,
                  borderRadius: BorderRadius.circular(inner),
                  elevation: 0,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(inner),
                    onTap: () => onChanged(v),
                    child: Container(
                      height: height,
                      padding: EdgeInsets.symmetric(horizontal: padding),
                      alignment: Alignment.center,
                      decoration: v == value && !dark
                          ? BoxDecoration(
                              borderRadius: BorderRadius.circular(inner),
                              boxShadow: [BoxShadow(color: c.shadow.withValues(alpha: 0.15), blurRadius: 2, offset: const Offset(0, 1))],
                            )
                          : null,
                      child: Text(
                        labels[i],
                        style: TextStyle(
                          fontSize: fontSize,
                          fontWeight: v == value ? (dark ? FontWeight.w600 : FontWeight.w700) : FontWeight.w500,
                          color: dark ? c.onInverse : c.text,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The page title in Newsreader ("September 2026", "Friday, Sep 25").
class CalendarTitle extends StatelessWidget {
  const CalendarTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 6),
    child: Semantics(
      header: true,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontFamily: FontFamilies.serif, fontSize: 30, letterSpacing: -0.3, color: context.colors.text),
      ),
    ),
  );
}

/// A white card with a hairline border and 14 px corners.
class CalendarCard extends StatelessWidget {
  const CalendarCard({super.key, required this.child, this.padding = EdgeInsets.zero, this.color, this.border});

  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  final BoxBorder? border;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: padding,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: color ?? c.surface,
        border: border ?? Border.all(color: c.line),
        borderRadius: BorderRadius.circular(14),
      ),
      child: child,
    );
  }
}

/// "TOP 3 TODAY", "SCHEDULE": 12 px, bold, spaced.
class CardLabel extends StatelessWidget {
  const CardLabel(this.text, {super.key, this.size = 12, this.color});

  final String text;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Text(
      text,
      style: TextStyle(fontSize: size, fontWeight: FontWeight.w700, letterSpacing: size * 0.08, color: color ?? context.colors.textMuted),
    ),
  );
}

/// The ‹ and › buttons.
class StepButtons extends StatelessWidget {
  const StepButtons({super.key, required this.onStep, required this.unit});

  final ValueChanged<int> onStep;

  /// "week", "day": "Previous week".
  final String unit;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      _Step(label: unit.isEmpty ? 'Previous' : 'Previous $unit', icon: EIcons.chevronLeft, onTap: () => onStep(-1)),
      _Step(label: unit.isEmpty ? 'Next' : 'Next $unit', icon: EIcons.chevronRight, onTap: () => onStep(1)),
    ],
  );
}

class _Step extends StatelessWidget {
  const _Step({required this.label, required this.icon, required this.onTap});

  final String label;
  final EIconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    excludeSemantics: true,
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: SizedBox(
        width: 44,
        height: 44,
        child: Center(child: EIcon(icon, size: 18, color: context.colors.text)),
      ),
    ),
  );
}
