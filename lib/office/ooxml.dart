import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import 'office_model.dart';

// The parts of Office Open XML (ECMA-376) shared by Word, PowerPoint and
// Excel: the zip package, its relationships, themes and colors.
//
// Elements and attributes are matched by their local name, whatever prefix
// the file gives them, so files from other apps (Google, LibreOffice,
// Keynote) read the same way.

/// EMUs (English Metric Units) in a point.
const emuPerPoint = 12700.0;

/// An Office file opened as a zip.
class OoxmlPackage {
  OoxmlPackage(Uint8List bytes) : _zip = _open(bytes);

  static Archive _open(Uint8List bytes) {
    if (bytes.length < 4 || bytes[0] != 0x50 || bytes[1] != 0x4B) {
      throw const OfficeReadError('This file isn’t a Word, PowerPoint or Excel file.');
    }
    try {
      return ZipDecoder().decodeBytes(bytes);
    } on Object {
      throw const OfficeReadError('This file can’t be opened. It may be damaged.');
    }
  }

  final Archive _zip;
  final _xml = <String, XmlDocument?>{};
  final _rels = <String, Map<String, Rel>>{};

  bool has(String path) => _zip.findFile(path) != null;

  /// A part's bytes, or null if the file has no such part.
  Uint8List? bytes(String path) {
    try {
      return _zip.findFile(path)?.readBytes();
    } on Object {
      return null;
    }
  }

  /// A part parsed as XML (once), or null if it's missing or not XML.
  XmlDocument? xml(String path) => _xml.putIfAbsent(path, () {
        final b = bytes(path);
        if (b == null) return null;
        try {
          return XmlDocument.parse(utf8.decode(b, allowMalformed: true));
        } on Object {
          return null;
        }
      });

  /// The relationships of [part], by id, with targets resolved to paths in
  /// the package.
  Map<String, Rel> rels(String part) => _rels.putIfAbsent(part, () {
        final dir = p.posix.dirname(part);
        final relsPath = p.posix.join(dir == '.' ? '' : dir, '_rels', '${p.posix.basename(part)}.rels');
        final doc = xml(relsPath);
        if (doc == null) return const {};
        return {
          for (final r in doc.rootElement.kids('Relationship'))
            ?r.attr('Id'): Rel(
                type: r.attr('Type') ?? '',
                target: r.attr('TargetMode') == 'External' ? '' : resolveTarget(dir, r.attr('Target') ?? ''),
              ),
        };
      });

  /// The first relationship of [part] whose type ends with [type].
  String? relOfType(String part, String type) =>
      rels(part).values.where((r) => r.type.endsWith('/$type') && r.target.isNotEmpty).firstOrNull?.target;
}

/// A relationship: its type and the path it points to ('' for links out
/// of the file).
class Rel {
  const Rel({required this.type, required this.target});

  final String type;
  final String target;
}

/// [target] relative to the folder [dir], as a path in the package.
String resolveTarget(String dir, String target) {
  if (target.startsWith('/')) return p.posix.normalize(target.substring(1));
  final base = dir == '.' ? '' : dir;
  return p.posix.normalize(p.posix.join(base, Uri.decodeFull(target)));
}

extension XmlBits on XmlElement {
  /// The first child element called [local] (any prefix).
  XmlElement? child(String local) {
    for (final e in childElements) {
      if (e.name.local == local) return e;
    }
    return null;
  }

  /// Child elements called [local].
  Iterable<XmlElement> kids(String local) => childElements.where((e) => e.name.local == local);

  /// Follows [locals] down, one child at a time.
  XmlElement? at(List<String> locals) {
    XmlElement? e = this;
    for (final l in locals) {
      e = e?.child(l);
      if (e == null) return null;
    }
    return e;
  }

  /// The attribute called [local], unprefixed if there is one.
  String? attr(String local) {
    String? prefixed;
    for (final a in attributes) {
      if (a.name.local != local) continue;
      if (a.name.prefix == null) return a.value;
      prefixed ??= a.value;
    }
    return prefixed;
  }

  /// A prefixed attribute called [local] (`r:id`, `r:embed`), which plain
  /// `id` attributes don't shadow.
  String? relAttr(String local) {
    for (final a in attributes) {
      if (a.name.local == local && a.name.prefix != null) return a.value;
    }
    return null;
  }

  double? number(String local) => double.tryParse(attr(local) ?? '');

  int? integer(String local) => int.tryParse(attr(local) ?? '');

  /// An on/off attribute: `1`, `true` and `on` are on.
  bool? flag(String local) {
    final v = attr(local);
    if (v == null) return null;
    return v == '1' || v == 'true' || v == 'on';
  }

  /// A Word on/off property element (`<w:b/>`, `<w:b w:val="0"/>`).
  bool? onOff(String local) {
    final e = child(local);
    if (e == null) return null;
    final v = e.attr('val');
    return v == null || !(v == '0' || v == 'false' || v == 'off' || v == 'none');
  }

  /// The [local] child's `val`.
  String? val(String local) => child(local)?.attr('val');

  /// Children with `mc:AlternateContent` opened up: [preferChoice] takes
  /// its first Choice (Word's drawings), else its Fallback (PowerPoint's
  /// pictures for content this version can't show).
  Iterable<XmlElement> open({bool preferChoice = false}) sync* {
    for (final e in childElements) {
      if (e.name.local != 'AlternateContent') {
        yield e;
        continue;
      }
      final choice = e.child('Choice'), fallback = e.child('Fallback');
      final pick = preferChoice ? (choice ?? fallback) : (fallback ?? choice);
      if (pick != null) yield* pick.open(preferChoice: preferChoice);
    }
  }
}

/// A theme's colors and fonts (`theme1.xml`).
class Theme {
  const Theme({this.colors = _officeColors, this.majorFont = 'Calibri Light', this.minorFont = 'Calibri'});

  factory Theme.read(XmlDocument? doc) {
    final elements = doc?.rootElement.at(['themeElements']);
    if (elements == null) return const Theme();
    final scheme = elements.child('clrScheme');
    final colors = {..._officeColors};
    for (final e in scheme?.childElements ?? const <XmlElement>[]) {
      final c = e.child('srgbClr')?.attr('val') ?? e.child('sysClr')?.attr('lastClr');
      final argb = c == null ? null : hexColor(c);
      if (argb != null) colors[e.name.local] = argb;
    }
    final fonts = elements.child('fontScheme');
    return Theme(
      colors: colors,
      majorFont: fonts?.at(['majorFont', 'latin'])?.attr('typeface') ?? 'Calibri Light',
      minorFont: fonts?.at(['minorFont', 'latin'])?.attr('typeface') ?? 'Calibri',
    );
  }

  final Map<String, int> colors;
  final String majorFont;
  final String minorFont;

  /// A theme font reference (`+mj-lt`, `+mn-lt`, `majorHAnsi`…) as a name.
  String font(String typeface) {
    if (typeface.startsWith('+mj') || typeface.startsWith('major')) return majorFont;
    if (typeface.startsWith('+mn') || typeface.startsWith('minor')) return minorFont;
    return typeface;
  }
}

/// The Office theme's colors, for files without a theme.
const _officeColors = {
  'dk1': 0xFF000000,
  'lt1': 0xFFFFFFFF,
  'dk2': 0xFF44546A,
  'lt2': 0xFFE7E6E6,
  'accent1': 0xFF4472C4,
  'accent2': 0xFFED7D31,
  'accent3': 0xFFA5A5A5,
  'accent4': 0xFFFFC000,
  'accent5': 0xFF5B9BD5,
  'accent6': 0xFF70AD47,
  'hlink': 0xFF0563C1,
  'folHlink': 0xFF954F72,
};

/// `RRGGBB` as an opaque ARGB color, or null.
int? hexColor(String hex) {
  if (hex.length != 6) return null;
  final v = int.tryParse(hex, radix: 16);
  return v == null ? null : 0xFF000000 | v;
}

/// How a slide's master maps `tx1`, `bg1`… to the theme's `dk1`, `lt1`…
typedef ColorMap = Map<String, String>;

const defaultColorMap = <String, String>{'tx1': 'dk1', 'bg1': 'lt1', 'tx2': 'dk2', 'bg2': 'lt2'};

/// The color in [parent] (an element holding `srgbClr`, `schemeClr`,
/// `sysClr` or `prstClr`), with its tint, shade, luminance and alpha
/// applied. [placeholder] stands for `phClr`.
int? readColor(XmlElement? parent, Theme theme, {ColorMap map = defaultColorMap, int? placeholder}) {
  if (parent == null) return null;
  for (final e in parent.childElements) {
    int? base;
    switch (e.name.local) {
      case 'srgbClr':
        base = hexColor(e.attr('val') ?? '');
      case 'sysClr':
        base = hexColor(e.attr('lastClr') ?? '') ?? (e.attr('val') == 'window' ? 0xFFFFFFFF : 0xFF000000);
      case 'schemeClr':
        final name = e.attr('val') ?? '';
        base = name == 'phClr' ? placeholder : theme.colors[map[name] ?? name];
      case 'prstClr':
        base = _presetColors[e.attr('val')];
      case 'scrgbClr':
        int ch(String n) => ((e.number(n) ?? 0) / 100000 * 255).round().clamp(0, 255);
        base = 0xFF000000 | ch('r') << 16 | ch('g') << 8 | ch('b');
      default:
        continue;
    }
    if (base == null) return null;
    return _modified(base, e);
  }
  return null;
}

const _presetColors = {
  'black': 0xFF000000,
  'white': 0xFFFFFFFF,
  'red': 0xFFFF0000,
  'green': 0xFF008000,
  'blue': 0xFF0000FF,
  'yellow': 0xFFFFFF00,
  'gray': 0xFF808080,
  'darkGray': 0xFFA9A9A9,
  'lightGray': 0xFFD3D3D3,
  'orange': 0xFFFFA500,
};

int _modified(int argb, XmlElement color) {
  var r = (argb >> 16 & 0xFF) / 255, g = (argb >> 8 & 0xFF) / 255, b = (argb & 0xFF) / 255;
  var a = (argb >>> 24) / 255;
  for (final m in color.childElements) {
    final v = (m.number('val') ?? 100000) / 100000;
    switch (m.name.local) {
      case 'lumMod' || 'lumOff':
        final (h, s, l) = _toHsl(r, g, b);
        final l2 = (m.name.local == 'lumMod' ? l * v : l + v).clamp(0.0, 1.0);
        (r, g, b) = _fromHsl(h, s, l2);
      case 'tint':
        r = 1 - (1 - r) * v;
        g = 1 - (1 - g) * v;
        b = 1 - (1 - b) * v;
      case 'shade':
        r *= v;
        g *= v;
        b *= v;
      case 'alpha':
        a = v.clamp(0.0, 1.0);
    }
  }
  int ch(double x) => (x.clamp(0.0, 1.0) * 255).round();
  return ch(a) << 24 | ch(r) << 16 | ch(g) << 8 | ch(b);
}

(double, double, double) _toHsl(double r, double g, double b) {
  final hi = math.max(r, math.max(g, b)), lo = math.min(r, math.min(g, b));
  final l = (hi + lo) / 2;
  if (hi == lo) return (0, 0, l);
  final d = hi - lo;
  final s = l > 0.5 ? d / (2 - hi - lo) : d / (hi + lo);
  final h = hi == r
      ? (g - b) / d + (g < b ? 6 : 0)
      : hi == g
          ? (b - r) / d + 2
          : (r - g) / d + 4;
  return (h / 6, s, l);
}

(double, double, double) _fromHsl(double h, double s, double l) {
  if (s == 0) return (l, l, l);
  double hue(double p, double q, double t) {
    if (t < 0) t += 1;
    if (t > 1) t -= 1;
    if (t < 1 / 6) return p + (q - p) * 6 * t;
    if (t < 1 / 2) return q;
    if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6;
    return p;
  }

  final q = l < 0.5 ? l * (1 + s) : l + s - l * s;
  final p = 2 * l - q;
  return (hue(p, q, h + 1 / 3), hue(p, q, h), hue(p, q, h - 1 / 3));
}

/// Typefaces drawn in the serif face (Newsreader); everything else is
/// drawn in Figtree.
bool isSerifFont(String name) {
  final n = name.toLowerCase();
  return const [
    'times', 'georgia', 'cambria', 'garamond', 'book antiqua', 'palatino', 'constantia', 'baskerville', //
    'bookman', 'century schoolbook', 'didot', 'bodoni', 'minion', 'merriweather', 'playfair', 'lora', //
    'noto serif', 'source serif', 'pt serif', 'liberation serif', 'dejavu serif', 'sitka', 'charter', 'hoefler',
  ].any(n.contains);
}

/// Text with only the characters a picture of it can draw: Office's private
/// symbol characters (Wingdings bullets) become a plain bullet.
String drawableText(String s) => s.replaceAll(RegExp('[-]'), '•');
