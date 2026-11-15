import 'dart:typed_data';

// The OpenGL ES self-test's scene and the pixels it checks. See
// RasterizerGpu.initialize.

/// A 160 x 160 SVG for the OpenGL ES self-test.
///
/// The self-test doesn't parse it: `src/ra_self_test.hpp` builds its shapes as
/// NanoSVG parses them, so that a parser's bug can't fail the GPU renderers.
/// A change here needs the same change there, which
/// `test/self_test_scene_test.dart` checks.
///
/// Drawn by the GPU renderer, its paths make each kind of entry that the core
/// writes for SVGs: opaques (the opaque paths' inner cells), instances, fast
/// and quad edges, and fast and quad molecules (the small paths). Back to
/// front:
/// - A: a red rectangle, opaque.
/// - B: a blue circle at half opacity, over A, so instances blend over
///   opaques.
/// - C: a green rectangle, opaque, over A and B. Its depth, written in the
///   passes before B's edges accumulate, must hide B's instances behind it.
/// - D: a magenta ring, opaque. Two concentric circles, filled even-odd, leave
///   its hole empty.
/// - E: a yellow disc at half opacity. Two concentric circles in the same
///   direction, filled non-zero, wind its middle twice, which must draw once.
/// - F and G: a small cyan square, and a small orange circle at 80% opacity.
///   They make molecules.
const selfTestSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" width="160" height="160" viewBox="0 0 160 160">
  <rect x="8" y="8" width="144" height="48" fill="#ff0000"/>
  <circle cx="80" cy="60" r="40" fill="#0000ff" fill-opacity="0.5"/>
  <rect x="96" y="40" width="44" height="44" fill="#00ff00"/>
  <path fill="#ff00ff" fill-rule="evenodd"
      d="M6,124 A30,30 0 1,0 66,124 A30,30 0 1,0 6,124 Z M21,124 A15,15 0 1,0 51,124 A15,15 0 1,0 21,124 Z"/>
  <path fill="#ffff00" fill-opacity="0.5"
      d="M100,128 A26,26 0 1,0 152,128 A26,26 0 1,0 100,128 Z M114,128 A12,12 0 1,0 138,128 A12,12 0 1,0 114,128 Z"/>
  <rect x="72" y="112" width="16" height="16" fill="#00ffff"/>
  <circle cx="80" cy="146" r="10" fill="#ffa500" fill-opacity="0.8"/>
</svg>
''';

/// The width and height of [selfTestSvg], in pixels.
const selfTestSize = 160;

/// A colour, not premultiplied, with each channel from 0 to 255.
typedef _Colour = ({int red, int green, int blue, int alpha});

// The paths' colours.
const _Colour _red = (red: 255, green: 0, blue: 0, alpha: 255),
    _blue = (red: 0, green: 0, blue: 255, alpha: 128),
    _green = (red: 0, green: 255, blue: 0, alpha: 255),
    _magenta = (red: 255, green: 0, blue: 255, alpha: 255),
    _yellow = (red: 255, green: 255, blue: 0, alpha: 128),
    _cyan = (red: 0, green: 255, blue: 255, alpha: 255),
    _orange = (red: 255, green: 165, blue: 0, alpha: 204);

/// The pixels to check, each with the paths over it, back to front.
///
/// Each one lies at least 3 pixels from every path's edge, so its colour is
/// exact, but for rounding. Some still lie near an edge, in the cells where
/// that edge's coverage accumulates.
const List<({int x, int y, List<_Colour> layers})> _probes = [
  (x: 4, y: 4, layers: []),
  (x: 20, y: 30, layers: [_red]),
  (x: 60, y: 30, layers: [_red, _blue]),
  (x: 80, y: 23, layers: [_red, _blue]), // B's top edge's cells
  (x: 80, y: 70, layers: [_blue]),
  (x: 80, y: 97, layers: [_blue]), // B's bottom edge's cells
  (x: 110, y: 50, layers: [_red, _blue, _green]), // C hides B
  (x: 130, y: 70, layers: [_green]),
  (x: 36, y: 100, layers: [_magenta]),
  (x: 36, y: 97, layers: [_magenta]), // D's outer edge's cells
  (x: 36, y: 112, layers: []), // D's hole, by its inner edge
  (x: 36, y: 124, layers: []),
  (x: 126, y: 128, layers: [_yellow]), // E's middle, wound twice
  (x: 126, y: 119, layers: [_yellow]), // by its inner circle's edge
  (x: 126, y: 108, layers: [_yellow]),
  (x: 150, y: 150, layers: []),
  (x: 80, y: 120, layers: [_cyan]),
  (x: 80, y: 146, layers: [_orange]),
  (x: 80, y: 139, layers: [_orange]),
];

/// The pixels that [checkSelfTest] checks.
Iterable<({int x, int y})> get selfTestPixels =>
    _probes.map((p) => (x: p.x, y: p.y));

/// The largest difference allowed in each channel from the expected colour,
/// for the rounding of alpha and of blending to 8 bits.
const _tolerance = 3;

/// Checks the scene's render, premultiplied, over transparent.
///
/// [rect] is the part of the scene in [rgba], in the scene's pixels. It lies
/// at [x0], [y0] in [rgba], which has [stride] bytes per row. The scene's
/// pixels outside [rect] count as transparent.
///
/// Returns null if every probe matches, else a description of the first that
/// doesn't.
String? checkSelfTest(
  Uint8List rgba,
  int stride,
  int x0,
  int y0,
  ({int left, int top, int width, int height}) rect,
) {
  final (:left, :top, :width, :height) = rect;
  for (final (:x, :y, :layers) in _probes) {
    // Source over, premultiplied.
    var r = 0.0, g = 0.0, b = 0.0, a = 0.0;
    for (final layer in layers) {
      final alpha = layer.alpha / 255;
      r = layer.red * alpha + r * (1 - alpha);
      g = layer.green * alpha + g * (1 - alpha);
      b = layer.blue * alpha + b * (1 - alpha);
      a = 255 * alpha + a * (1 - alpha);
    }
    final inside =
        x >= left && x < left + width && y >= top && y < top + height;
    final i = (y - top + y0) * stride + 4 * (x - left + x0);
    final actual = inside
            ? [rgba[i], rgba[i + 1], rgba[i + 2], rgba[i + 3]]
            : [0, 0, 0, 0],
        expected = [r, g, b, a];
    for (var k = 0; k < 4; k++) {
      if ((actual[k] - expected[k]).abs() > _tolerance) {
        return 'pixel $x,$y is $actual, not '
            '${[for (final v in expected) v.round()]}';
      }
    }
  }
  return null;
}
