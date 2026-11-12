import 'dart:ui';

/// The game's own font of straight lines: capitals, digits, a space, a colon,
/// a period and a dash.
///
/// Each glyph is polylines through the points of a grid [width] wide and
/// [capHeight] tall, half points included, with y down and the baseline at
/// the bottom. Like the shapes, glyphs are stroked [stroke] wide, with miter
/// joins and square ends. The font makes each glyph's path once, and all the
/// glyph's components share it, so each glyph costs one import.
///
/// No join is sharper than 60°, so that its miter stays within a stroke's
/// width of its point, whatever the renderer's miter limit. Sharper corners
/// are two polylines.
abstract final class TubeFont() {
  static const width = 4.0;
  static const capHeight = 6.0;

  /// From one glyph's left edge to the next's: the glyph's width, plus a gap
  /// of 2.
  static const advance = 6.0;

  /// The strokes' width, an eighth of the cap height.
  static const stroke = capHeight / 8;

  /// The glyph of [char], or null for a space. A lowercase letter gets its
  /// capital's glyph.
  ///
  /// Throws an [ArgumentError] for a character without a glyph.
  static Path? glyph(String char) {
    final upper = char.toUpperCase();
    if (upper == ' ') {
      return null;
    }
    final glyph = _glyphs[upper];
    if (glyph == null) {
      throw ArgumentError.value(char, 'char', 'No glyph');
    }
    return glyph;
  }

  /// The width of [text], from its first glyph's left edge to its last
  /// glyph's right edge, not counting the strokes' ends.
  static double widthOf(String text) =>
      text.isEmpty ? 0 : text.length * advance - (advance - width);

  static final _glyphs = {
    for (final MapEntry(key: char, value: polylines) in _polylines.entries)
      char: _path(polylines),
  };

  /// Each glyph's polylines, with their points written as in an SVG polyline.
  ///
  /// A closed shape starts and ends in the middle of a straight line, where
  /// its square ends meet unseen.
  static const _polylines = {
    'A': ['0,6 0,2 2,0 4,2 4,6', '0,4 4,4'],
    'B': ['0,3 3,3 4,4 4,5 3,6 0,6 0,0 3,0 4,1 4,2 3,3'],
    'C': ['4,0 1,0 0,1 0,5 1,6 4,6'],
    'D': ['2,0 3,0 4,1 4,5 3,6 0,6 0,0 2,0'],
    'E': ['4,0 0,0 0,6 4,6', '0,3 3,3'],
    'F': ['4,0 0,0 0,6', '0,3 3,3'],
    'G': ['4,1 3,0 1,0 0,1 0,5 1,6 3,6 4,5 4,3 2,3'],
    'H': ['0,0 0,6', '4,0 4,6', '0,3 4,3'],
    'I': ['1,0 3,0', '2,0 2,6', '1,6 3,6'],
    'J': ['4,0 4,5 3,6 1,6 0,5 0,4'],
    'K': ['0,0 0,6', '4,0 0,4', '1.5,2.5 4,6'],
    'L': ['0,0 0,6 4,6'],
    'M': ['0,6 0,0', '4,6 4,0', '0,0 2,3 4,0'],
    'N': ['0,6 0,0', '4,0 4,6', '0,0 4,6'],
    'O': ['2,0 3,0 4,1 4,5 3,6 1,6 0,5 0,1 1,0 2,0'],
    'P': ['0,6 0,0 3,0 4,1 4,2 3,3 0,3'],
    'Q': ['2,0 3,0 4,1 4,5 3,6 1,6 0,5 0,1 1,0 2,0', '2,4 4,6'],
    'R': ['0,6 0,0 3,0 4,1 4,2 3,3 0,3', '2,3 4,6'],
    'S': ['4,1 3,0 1,0 0,1 0,2 1,3 3,3 4,4 4,5 3,6 1,6 0,5'],
    'T': ['0,0 4,0', '2,0 2,6'],
    'U': ['0,0 0,5 1,6 3,6 4,5 4,0'],
    'V': ['0,0 0,3 2,6 4,3 4,0'],
    'W': ['0,0 0,6', '4,0 4,6', '0,6 2,3 4,6'],
    'X': ['0,0 4,6', '4,0 0,6'],
    'Y': ['0,0 2,3 4,0', '2,3 2,6'],
    'Z': ['0,0 4,0 4,1 0,5 0,6 4,6'],
    '0': ['2,0 3,0 4,1 4,5 3,6 1,6 0,5 0,1 1,0 2,0', '2.5,2 1.5,4'],
    '1': ['1,0 2,0 2,6', '1,6 3,6'],
    '2': ['0,1 1,0 3,0 4,1 4,2 0,5 0,6 4,6'],
    '3': ['0,1 1,0 3,0 4,1 4,2 3,3 4,4 4,5 3,6 1,6 0,5', '1,3 3,3'],
    '4': ['0,0 0,4 4,4', '3,2 3,6'],
    '5': ['4,0 0,0 0,3 3,3 4,4 4,5 3,6 0,6'],
    '6': ['3,0 1,0 0,1 0,5 1,6 3,6 4,5 4,4 3,3 0,3'],
    '7': ['0,0 4,0 4,1 1,6'],
    '8': [
      '2,0 3,0 4,1 4,2 3,3 1,3 0,2 0,1 1,0 2,0',
      '2,3 3,3 4,4 4,5 3,6 1,6 0,5 0,4 1,3 2,3',
    ],
    '9': ['4,3 1,3 0,2 0,1 1,0 3,0 4,1 4,5 3,6 1,6'],
    ':': ['2,1.75 2,2', '2,5.75 2,6'],
    '.': ['2,5.75 2,6'],
    '-': ['1,3 3,3'],
  };

  static Path _path(List<String> polylines) {
    final path = Path();
    for (final polyline in polylines) {
      path.addPolygon([
        for (final point in polyline.split(' '))
          switch (point.split(',').map(double.parse).toList()) {
            [final x, final y] => Offset(x, y),
            _ => throw ArgumentError.value(point, 'point'),
          },
      ], false);
    }
    return path;
  }
}
