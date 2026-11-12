import 'dart:ui' as ui;

/// [paint]'s miter limit.
///
/// dart:ui's setter stores the limit less its default, 4, and its getter
/// returns what's stored (Flutter 3.47). So a new paint's limit reads 0, and
/// copying the getter's value to another paint takes 4 off its limit. The
/// offset is measured once, on a paint whose limit is known, in case Flutter
/// fixes this.
double miterLimitOf(ui.Paint paint) =>
    paint.strokeMiterLimit + _miterLimitOffset;

final double _miterLimitOffset =
    4 - (ui.Paint()..strokeMiterLimit = 4).strokeMiterLimit;

/// The paths that the canvas renderer's scenes draw with dart:ui.
///
/// They're an SVG's paths (`SvgPaths`), or plain paths and their paints
/// (`ScenePaths`).
abstract interface class CanvasPaths() {
  /// The paths' bounds, grown by half of each stroke's width.
  ///
  /// It's [ui.Rect.zero] if there are no paths.
  ui.Rect get bounds;

  /// The rectangle that the paths' coordinates are in.
  ///
  /// It's an SVG's own view box, or the bounds of plain paths.
  ui.Rect get viewBox;

  /// The area that [draw] can paint.
  ///
  /// It holds the paths with all of their strokes, joins and caps. It's
  /// [ui.Rect.zero] if there are no paths.
  ui.Rect get paintedBounds;

  /// The number of draw calls that [draw] makes.
  int get drawCount;

  /// Draws the paths into [canvas], in their own coordinates.
  ///
  /// [opacity] scales each path's alpha, so paths that overlap show through
  /// each other. [colorFilter], if any, filters each path's color.
  void draw(
    ui.Canvas canvas, {
    double opacity = 1,
    ui.ColorFilter? colorFilter,
  });
}
