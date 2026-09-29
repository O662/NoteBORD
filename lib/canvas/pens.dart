import 'dart:ui';

import '../board/model.dart';
import '../theme/tokens.g.dart' as tokens;

/// Thickness choices from the pen popover (Canvas.dc.html `sizeDefs`).
class PenSize {
  const PenSize(this.label, this.width, this.dotPx);

  final String label;

  /// Stroke width in page px at medium pressure.
  final double width;

  /// Size of the dot shown on the thickness button.
  final double dotPx;
}

const penSizes = [
  PenSize('0.3 mm', 1.5, 4),
  PenSize('0.5 mm', 2.5, 6),
  PenSize('0.8 mm', 4, 9),
  PenSize('1.2 mm', 6, 13),
  PenSize('2.0 mm', 10, 18),
];

/// The marker draws 4× wider at 40% opacity.
const markerWidthFactor = 4.0;
const markerOpacity = 0.4;

double strokeWidthFor(InkTool tool, int sizeIndex) =>
    penSizes[sizeIndex].width * (tool == InkTool.marker ? markerWidthFactor : 1);

double inkOpacity(InkTool tool, PenType type) => switch ((tool, type)) {
      (InkTool.marker, _) => markerOpacity,
      (_, PenType.pencil) => 0.85,
      _ => 1.0,
    };

/// Width multiplier for a normalized pressure (0..1). Medium pressure is 1×.
double pressureFactor(PenType type, double pressure) {
  final p = pressure.clamp(0.0, 1.0);
  return switch (type) {
    PenType.ballpoint => 0.45 + 1.1 * p,
    PenType.fountain => 0.25 + 1.5 * p,
    PenType.pencil => 0.65 + 0.7 * p,
  };
}

String penTypeLabel(PenType t) => switch (t) {
      PenType.ballpoint => 'Ballpoint',
      PenType.fountain => 'Fountain',
      PenType.pencil => 'Pencil',
    };

/// The popover palette, in design order.
final List<Color> popoverPalette = [
  tokens.inkDefaults[0],
  tokens.inkDefaults[1],
  tokens.extraInkDefaults[4],
  tokens.extraInkDefaults[0],
  tokens.inkDefaults[2],
  tokens.extraInkDefaults[1],
  tokens.extraInkDefaults[2],
  tokens.extraInkDefaults[3],
  tokens.extraInkDefaults[5],
];

final Map<int, String> _names = {
  for (final (i, n) in ['Ink black', 'Deep blue', 'Terracotta'].indexed) tokens.inkDefaults[i].toARGB32(): n,
  for (final (i, n) in ['Green', 'Red', 'Plum', 'Amber', 'Sky blue', 'Graphite'].indexed)
    tokens.extraInkDefaults[i].toARGB32(): n,
  for (final (i, n) in ['Teal', 'Pink', 'Brown', 'Olive'].indexed) tokens.extraInkAddable[i].toARGB32(): n,
};

String colorName(Color c) => _names[c.toARGB32()] ?? colorToHex(c);
