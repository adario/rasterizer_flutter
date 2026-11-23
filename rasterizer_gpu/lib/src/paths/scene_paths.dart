// The plain paths or polygons, and paints, that RasterizerScene.fromPaths and
// fromPolygons copy. The canvas renderer draws them with dart:ui. The GPU
// renderers flatten paths once into contours, and take polygons as they are.
//
// This file uses no dart:ffi, as the canvas renderer also draws on the web.

import 'dart:math' show max;
import 'dart:ui' as ui;

import '../../rasterizer_gpu.dart'
    show
        RasterizerGlow,
        RasterizerPaintedPath,
        RasterizerPaintedPolygons,
        RasterizerPolygons;
import '../canvas_paths.dart';
import '../svg_paths/svg_paths.dart';
import 'path_contours.dart';

/// Returns why the GPU renderers can't draw with [paint], or null if they can.
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

/// A path scene's paths or polygons, and their paints, in paint order.
///
/// It keeps a copy of each paint, which the canvas renderer draws with, and
/// each distinct path or polygons once, to make into contours.
class ScenePaths._(
  /// The distinct shapes, in the order they're first drawn: each a [ui.Path]
  /// or [RasterizerPolygons].
  final List<Object> shapes,

  /// Each draw's shape, as its index in [shapes].
  final List<int> pathIndices,

  /// Each draw's copy of its paint, a fill or a stroke.
  final List<ui.Paint> paints,
  @override final ui.Rect viewBox,
  @override final ui.Rect bounds,
  @override final ui.Rect paintedBounds,

  /// The glow around the paths. Only the mesh renderer's import reads it.
  final RasterizerGlow? glow,

  /// Whether the mesh renderer fills each polygon on its own, rather than
  /// their union (see `RasterizerScene.fromPolygons`).
  final bool separate,
) implements CanvasPaths {
  /// Keeps [paths]' paths and copies their paints.
  ///
  /// Throws [ArgumentError] for a paint that the GPU renderers can't draw
  /// ([undrawable]).
  factory ScenePaths(
    List<RasterizerPaintedPath> paths, {
    RasterizerGlow? glow,
  }) => ScenePaths._of(
    [for (final (:path, :paint) in paths) (shape: path, paint: paint)],
    (shape) => (shape as ui.Path).getBounds(),
    'paths',
    glow,
    false,
  );

  /// Keeps [polygons]' polygons and copies their paints, as [ScenePaths.new]
  /// does with paths.
  factory ScenePaths.polygons(
    List<RasterizerPaintedPolygons> polygons, {
    RasterizerGlow? glow,
    bool separate = false,
  }) => ScenePaths._of(
    [
      for (final (:polygons, :paint) in polygons)
        (shape: polygons, paint: paint),
    ],
    (shape) => (shape as RasterizerPolygons).bounds,
    'polygons',
    glow,
    separate,
  );

  /// Keeps [draws]' shapes, whose bounds [boundsOf] returns, and copies their
  /// paints. A paint that the GPU renderers can't draw throws, naming its
  /// draw in [name].
  factory ScenePaths._of(
    List<({Object shape, ui.Paint paint})> draws,
    ui.Rect Function(Object shape) boundsOf,
    String name,
    RasterizerGlow? glow,
    bool separate,
  ) {
    final distinct = <Object>[];
    final indices = Map<Object, int>.identity();
    final pathIndices = <int>[];
    final paints = <ui.Paint>[];
    ui.Rect? viewBox, bounds, painted;
    for (final (i, (:shape, :paint)) in draws.indexed) {
      final reason = undrawable(paint);
      if (reason != null) {
        throw ArgumentError.value(
          paint,
          '$name[$i]',
          '$reason, which the GPU renderers can\'t draw',
        );
      }
      pathIndices.add(
        indices.putIfAbsent(shape, () {
          distinct.add(shape);
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
      paints.add(copy);
      final stroke = copy.style == ui.PaintingStyle.stroke ? copy : null;
      // An empty shape's bounds are zero, so they would stretch the bounds to
      // the origin.
      final b = boundsOf(shape);
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
      paints,
      viewBox ?? ui.Rect.zero,
      bounds ?? ui.Rect.zero,
      painted ?? ui.Rect.zero,
      glow,
      separate,
    );
  }

  /// Each path's contours, at the last tolerance it was flattened to, kept
  /// while the path lives. Polygons' contours fit any tolerance.
  ///
  /// This takes paths and polygons as immutable.
  static final _contours = Expando<({double tolerance, PathContours contours})>(
    'contours',
  );

  /// Each draw: its path and its paint, for the canvas renderer, made the
  /// first time it's read. Polygons make their path then.
  late final List<VectorPath> draws = [
    for (final (i, paint) in paints.indexed)
      VectorPath(
        _pathOf(shapes[pathIndices[i]]),
        paint.style == ui.PaintingStyle.stroke
            ? VectorPaint(stroke: paint)
            : VectorPaint(fill: paint),
      ),
  ];

  /// Returns whether draw [i] fills with the even-odd rule. Polygons fill
  /// with the non-zero one.
  bool isEvenOdd(int i) => switch (shapes[pathIndices[i]]) {
    final ui.Path path => path.fillType == ui.PathFillType.evenOdd,
    _ => false,
  };

  static ui.Path _pathOf(Object shape) => switch (shape) {
    final ui.Path path => path,
    _ => (shape as RasterizerPolygons).path,
  };

  @override
  int get drawCount => paints.length;

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

  /// Returns the tolerance to flatten the paths to, in their units.
  ///
  /// It's 1/4 of a device pixel when [viewBox]'s longer side, or the widest
  /// stroke if that's wider, spans [maxSize] device pixels. It's at least 16
  /// float steps of the farthest coordinate. A finer tolerance would flatten a
  /// tiny path down to each sample's rounding error, or its round joins and
  /// caps into thousands of triangles. libtess can take seconds to tessellate
  /// those, or never finish.
  double tolerance(double maxSize) {
    var side = max(viewBox.width, viewBox.height);
    for (final paint in paints) {
      if (paint.style == ui.PaintingStyle.stroke) {
        side = max(side, paint.strokeWidth);
      }
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

  /// Returns the contours of each of [shapes]: a path's flattened to the
  /// [tolerance] for [maxSize], and polygons' as they are.
  ///
  /// A path already flattened to the same tolerance, for any scene, reuses
  /// its contours, as polygons always do.
  List<PathContours> contours(double maxSize) {
    final tolerance = this.tolerance(maxSize);
    return [for (final shape in shapes) _contoursOf(shape, tolerance)];
  }

  static PathContours _contoursOf(Object shape, double tolerance) {
    final kept = _contours[shape];
    if (shape is RasterizerPolygons) {
      if (kept != null) {
        return kept.contours;
      }
      final contours = PathContours.polygons(
        shape.vertices,
        shape.vertexCounts,
      );
      _contours[shape] = (tolerance: 0, contours: contours);
      return contours;
    }
    if (kept != null && kept.tolerance == tolerance) {
      return kept.contours;
    }
    final contours = PathContours([shape as ui.Path], tolerance: tolerance);
    _contours[shape] = (tolerance: tolerance, contours: contours);
    return contours;
  }
}
