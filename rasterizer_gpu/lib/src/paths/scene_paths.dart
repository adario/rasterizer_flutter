// The plain paths and paints that RasterizerScene.fromPaths copies. The
// canvas renderer draws them with dart:ui. The GPU renderers flatten them once
// into contours.
//
// This file uses no dart:ffi, as the canvas renderer also draws on the web.

import 'dart:math' show max;
import 'dart:ui' as ui;

import '../../rasterizer_gpu.dart' show RasterizerGlow;
import '../canvas_paths.dart';
import '../svg_paths/svg_paths.dart';
import 'path_contours.dart';

/// Why the GPU renderers can't draw with [paint], or null if they can.
///
/// They draw a color in sRGB, with [ui.BlendMode.srcOver] and antialiasing,
/// as a fill or as a stroke of a positive width. [ScenePaths] keeps only those
/// fields of a paint.
String? undrawable(ui.Paint paint) {
  if (paint.shader != null) {
    return 'A shader';
  }
  if (paint.colorFilter != null) {
    return 'A color filter';
  }
  if (paint.maskFilter != null) {
    return 'A mask filter';
  }
  if (paint.imageFilter != null) {
    return 'An image filter';
  }
  if (paint.blendMode != ui.BlendMode.srcOver) {
    return 'The blend mode ${paint.blendMode.name}';
  }
  if (paint.invertColors) {
    return 'Inverted colors';
  }
  if (!paint.isAntiAlias) {
    return 'No antialiasing';
  }
  if (paint.color.colorSpace != ui.ColorSpace.sRGB) {
    return 'A color in ${paint.color.colorSpace.name}';
  }
  final width = paint.strokeWidth;
  if (paint.style == ui.PaintingStyle.stroke &&
      (!width.isFinite || width <= 0)) {
    // A hairline is a device pixel wide under any transform, so it can't be
    // imported once.
    return 'A stroke ${width == 0 ? 'hairline' : 'width of $width'}';
  }
  return null;
}

/// A path scene's paths and paints, in paint order.
///
/// It keeps a copy of each paint, which the canvas renderer draws with, and
/// each distinct path once, to flatten into contours.
class ScenePaths._(
  /// The distinct paths, in the order they're first drawn.
  final List<ui.Path> paths,

  /// Each draw's path, as its index in [paths].
  final List<int> pathIndices,

  /// Each draw: its path and a copy of its paint, a fill or a stroke.
  final List<VectorPath> draws,
  @override final ui.Rect viewBox,
  @override final ui.Rect bounds,
  @override final ui.Rect paintedBounds,

  /// The glow around the paths. Only the mesh renderer's import reads it.
  final RasterizerGlow? glow,
) implements CanvasPaths {
  /// Keeps [paths]' paths and copies their paints.
  ///
  /// Throws [ArgumentError] for a paint that the GPU renderers can't draw
  /// ([undrawable]).
  factory ScenePaths(List<(ui.Path, ui.Paint)> paths, {RasterizerGlow? glow}) {
    final distinct = <ui.Path>[];
    final indices = Map<ui.Path, int>.identity();
    final pathIndices = <int>[];
    final draws = <VectorPath>[];
    ui.Rect? viewBox, bounds, painted;
    for (final (i, (path, paint)) in paths.indexed) {
      final reason = undrawable(paint);
      if (reason != null) {
        throw ArgumentError.value(
          paint,
          'paths[$i]',
          '$reason, which the GPU renderers can\'t draw',
        );
      }
      pathIndices.add(
        indices.putIfAbsent(path, () {
          distinct.add(path);
          return distinct.length - 1;
        }),
      );
      final copy = ui.Paint()
        ..color = paint.color
        ..style = paint.style
        ..strokeWidth = paint.strokeWidth
        ..strokeCap = paint.strokeCap
        ..strokeJoin = paint.strokeJoin
        ..strokeMiterLimit = miterLimitOf(paint);
      final stroke = copy.style == ui.PaintingStyle.stroke ? copy : null;
      draws.add(
        VectorPath(
          path,
          stroke == null
              ? VectorPaint(fill: copy)
              : VectorPaint(stroke: stroke),
        ),
      );
      // An empty path's bounds are zero, so they would stretch the bounds to
      // the origin.
      final b = path.getBounds();
      if (b == ui.Rect.zero) {
        continue;
      }
      viewBox = viewBox?.expandToInclude(b) ?? b;
      final s = b.inflate(stroke == null ? 0 : stroke.strokeWidth / 2);
      bounds = bounds?.expandToInclude(s) ?? s;
      final p = SvgPaths.paintedBoundsOf(b, stroke);
      painted = painted?.expandToInclude(p) ?? p;
    }
    return ScenePaths._(
      distinct,
      pathIndices,
      draws,
      viewBox ?? ui.Rect.zero,
      bounds ?? ui.Rect.zero,
      painted ?? ui.Rect.zero,
      glow,
    );
  }

  /// Each path's contours, at the last tolerance it was flattened to, kept
  /// while the path lives.
  ///
  /// This takes paths as immutable.
  static final _contours = Expando<(double, PathContours)>('contours');

  @override
  int get drawCount => draws.length;

  @override
  void draw(
    ui.Canvas canvas, {
    double opacity = 1,
    ui.ColorFilter? colorFilter,
  }) {
    for (final draw in draws) {
      draw.draw(canvas, opacity: opacity, colorFilter: colorFilter);
    }
  }

  /// The tolerance the paths are flattened to, in their units.
  ///
  /// It's 1/4 of a device pixel when [viewBox]'s longer side, or the widest
  /// stroke if that's wider, spans [maxSize] device pixels. It's at least 16
  /// float steps of the farthest coordinate. A finer tolerance would flatten a
  /// tiny path down to each sample's rounding error, or its round joins and
  /// caps into thousands of triangles. libtess can take seconds to tessellate
  /// those, or never finish.
  double tolerance(double maxSize) {
    var side = max(viewBox.width, viewBox.height);
    for (final draw in draws) {
      side = max(side, draw.paint.stroke?.strokeWidth ?? 0);
    }
    final farthest = [
      bounds.left,
      bounds.top,
      bounds.right,
      bounds.bottom,
    ].fold(0.0, (m, v) => max(m, v.abs()));
    return max(0.25 * (side > 0 ? side : 1) / maxSize, _floatSteps * farthest);
  }

  /// 16 float32 steps, as a fraction of a coordinate's magnitude.
  ///
  /// Float32s hold the contours' points and the meshes' vertices.
  static const _floatSteps = 16 / (1 << 23);

  /// The contours of each of [paths], flattened to the [tolerance] for
  /// [maxSize].
  ///
  /// A path already flattened to the same tolerance, for any scene, reuses
  /// its contours.
  List<PathContours> contours(double maxSize) {
    final tolerance = this.tolerance(maxSize);
    return [for (final path in paths) _contoursOf(path, tolerance)];
  }

  static PathContours _contoursOf(ui.Path path, double tolerance) {
    final kept = _contours[path];
    if (kept != null && kept.$1 == tolerance) {
      return kept.$2;
    }
    final contours = PathContours([path], tolerance: tolerance);
    _contours[path] = (tolerance, contours);
    return contours;
  }
}
