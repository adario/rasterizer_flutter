import 'dart:collection' show UnmodifiableListView;
import 'dart:math' show max, min;

import 'package:flame/cache.dart';
import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/extensions.dart';
import 'package:flame/geometry.dart';
import 'package:flame_rasterizer/src/rasterizer_svg.dart';
import 'package:flame_rasterizer/src/rasterizer_svg_component.dart';
import 'package:flutter/foundation.dart' show protected;
import 'package:rasterizer_gpu/rasterizer_gpu.dart';

/// A Flame [PathHitbox] in the shape of an SVG's paths, made from an
/// [outline] such as [RasterizerSvg.outline].
///
/// Its parent is a component such as a [RasterizerSvgComponent]. The hitbox
/// stretches the outline's rect to the parent's size, as the component draws
/// the SVG, and again whenever that size changes.
///
/// ```dart
/// final coin = await RasterizerSvg.load('assets/coin.svg');
/// final size = Vector2.all(64);
/// world.add(
///   RasterizerSvgComponent(svg: coin, size: size)
///     ..add(SvgHitbox(coin.outline, size: size)),
/// );
/// ```
///
/// Its polygons come from the outline's closed contours (see
/// [PathComponent.new]). The outline closes the contours of filled paths, as
/// SVG fills them. Stroked-only paths collide along their middle, and their
/// open contours not at all.
///
/// Making the polygons is most of what a hitbox costs. So the hitboxes of an
/// outline sampled the same way, such as for the same size, share them, for
/// the last 8 ways it was sampled. The outline's path must not change once it
/// has hitboxes, nor the vertices of their polygons.
///
/// Its [aabb], which the collision detection needs again each frame the
/// hitbox moves, is the box around its polygons' bounds. It transforms only
/// the bounds' 4 corners, under its and its ancestors' transforms composed
/// once, rather than all the polygons' vertices, as [PathHitbox] does. The
/// box is as tight, except while the hitbox is turned by other than right
/// angles. The polygons are transformed only when the box overlaps another
/// hitbox's.
class SvgHitbox(
  /// The SVG outline that the hitbox is made from.
  final SvgOutline outline, {
  Vector2? size,
  double sampling = 1,
  double? tolerance,
  super.filter,
  super.isSolid,
  super.collisionType,
}) extends PathHitbox {
  /// Creates a hitbox from [outline], for a parent of [size].
  ///
  /// The polygons are sampled every [sampling], and simplified within
  /// [tolerance], half the sampling by default, both in the units of [size].
  /// [size] defaults to the outline's rect's. See [PathComponent.new], also
  /// for [filter].
  this
    : super(
        // PathComponent samples its path in its constructor. An empty path
        // makes that free, and the body takes the shared polygons instead.
        path: Path(),
        sampling: sampling / _units(outline, size),
        tolerance: tolerance == null ? null : tolerance / _units(outline, size),
      ) {
    final shared = _Shared.of(outline);
    _path = shared.path;
    _polygons = shared.sampled(this.sampling, this.tolerance, filter: filter);
    // PathComponent sized the hitbox to its empty path.
    final bounds = outline.path.getBounds();
    this.size.setValues(bounds.width, bounds.height);
  }

  /// Parent units per SVG unit for [size]: the larger of its two scales, so
  /// that the polygons aren't sampled more coarsely than asked in either
  /// direction.
  static double _units(SvgOutline outline, Vector2? size) {
    final rect = outline.rect;
    if (size == null || rect.isEmpty) {
      return 1;
    }
    final units = max(size.x / rect.width, size.y / rect.height);
    return units > 0 && units.isFinite ? units : 1;
  }

  /// The outline's path rooted at the origin, as [PathComponent.path], shared
  /// with the outline's other hitboxes.
  @override
  Path get path => _path ?? super.path;

  // Null while PathComponent's constructor reads [path] to sample it.
  Path? _path;

  @override
  void onParentResize(Vector2 maxSize) {
    super.onParentResize(maxSize);
    place(maxSize);
  }

  /// Stretches the outline's rect to [size], as [RasterizerSvgComponent] draws
  /// its SVG.
  ///
  /// The hitbox calls it with its parent's size when it's mounted, and
  /// whenever that size changes. The polygons keep the sampling they were
  /// made with.
  void place(Vector2 size) {
    final rect = outline.rect;
    if (rect.isEmpty) {
      return;
    }
    final sx = size.x / rect.width;
    final sy = size.y / rect.height;
    // The path's polygons are rooted at its bounds' top left.
    final bounds = outline.path.getBounds();
    position.setValues(
      (bounds.left - rect.left) * sx,
      (bounds.top - rect.top) * sy,
    );
    scale.setValues(sx, sy);
  }

  // PathComponent keeps its polygons, and what it derives from them, private.
  // So the members below that read them copy PathComponent's, but read the
  // shared polygons. PathComponent's other members reach the polygons through
  // these.

  late final _Polygons _polygons;

  // Its polygons' vertices and edges in the game's coordinates, overwritten
  // as it moves.
  late final _globalPolygons = [
    for (final polygon in _polygons.vertices)
      List.generate(polygon.length, (_) => Vector2.zero(), growable: false),
  ];
  late final _lineSegments = [
    for (final polygon in _polygons.vertices)
      List.generate(polygon.length, (_) => LineSegment.zero(), growable: false),
  ];
  final _cachedGlobalPolygons = ValueCache<List<List<Vector2>>>();

  @override
  UnmodifiableListView<UnmodifiableListView<Vector2>> get polygons =>
      _polygons.view;

  @override
  @protected
  Path get polygonsPath => _polygons.path;

  @override
  List<List<Vector2>> globalPolygons() {
    final scale = absoluteScale;
    final shouldReverse = scale.y.isNegative ^ scale.x.isNegative;
    final angle = absoluteAngle;
    final position = absoluteTopLeftPosition;
    if (!_cachedGlobalPolygons.isCacheValid<dynamic>(<dynamic>[
      position,
      size,
      scale,
      angle,
    ])) {
      final polygons = _polygons.vertices;
      for (var i = 0; i < polygons.length; i++) {
        final polygon = polygons[i];
        final globalPolygon = _globalPolygons[i];
        for (var j = 0; j < polygon.length; j++) {
          globalPolygon[j].setFrom(absolutePositionOf(polygon[j]));
        }
        if (shouldReverse) {
          // Mirrored, the vertices go clockwise. Reversed, they go
          // counterclockwise again.
          globalPolygon.reverse();
        }
      }
      _cachedGlobalPolygons.updateCache<dynamic>(_globalPolygons, <dynamic>[
        position.clone(),
        size.clone(),
        scale.clone(),
        angle,
      ]);
    }
    return _cachedGlobalPolygons.value!;
  }

  @override
  bool containsLocalPoint(Vector2 point) {
    // Checks in the game's coordinates, as PathComponent's check of local
    // points is private.
    return containsPoint(absolutePositionOf(point));
  }

  @override
  List<LineSegment> possibleIntersectionVertices(Rect? rect) {
    final rectIntersections = <LineSegment>[];
    if ((rect?.width == 0) ||
        (rect?.height == 0) ||
        width == 0 ||
        height == 0) {
      return rectIntersections;
    }
    final polygons = globalPolygons();
    for (var i = 0; i < polygons.length; i++) {
      final vertices = polygons[i];
      final lineSegments = _lineSegments[i];
      for (var j = 0; j < vertices.length; j++) {
        final edge = lineSegments[j]
          ..from.setFrom(vertices[j])
          ..to.setFrom(vertices[(j + 1) % vertices.length]);
        if (rect?.intersectsSegment(edge.from, edge.to) ?? true) {
          rectIntersections.add(edge);
        }
      }
    }
    return rectIntersections;
  }

  @override
  void renderDebugMode(Canvas canvas) {
    // PathComponent's draws its own polygons' path, which is empty here.
    super.renderDebugMode(canvas);
    canvas.drawPath(polygonsPath, debugPaint);
  }

  /// Sets [aabb] to the box around its polygons' bounds, as the class
  /// describes.
  @override
  void computeAabb(Aabb2 aabb) {
    final bounds = _polygons.bounds;
    if (bounds == null) {
      super.computeAabb(aabb);
      return;
    }
    // The map from its local coordinates to the game's, as absolutePositionOf
    // maps them, composed once rather than for each corner:
    // x' = a x + c y + tx, y' = b x + d y + ty.
    var m = transform.transformMatrix.storage;
    var (a, b, c, d, tx, ty) = (m[0], m[1], m[4], m[5], m[12], m[13]);
    for (var ancestor = parent; ancestor != null; ancestor = ancestor.parent) {
      if (ancestor is! PositionComponent) {
        continue;
      }
      m = ancestor.transform.transformMatrix.storage;
      (a, b, c, d, tx, ty) = (
        m[0] * a + m[4] * b,
        m[1] * a + m[5] * b,
        m[0] * c + m[4] * d,
        m[1] * c + m[5] * d,
        m[0] * tx + m[4] * ty + m[12],
        m[1] * tx + m[5] * ty + m[13],
      );
    }
    // Each coordinate's least and most, from the least and most of each of
    // its terms.
    final (ax0, ax1) = (a * bounds.left, a * bounds.right);
    final (bx0, bx1) = (b * bounds.left, b * bounds.right);
    final (cy0, cy1) = (c * bounds.top, c * bounds.bottom);
    final (dy0, dy1) = (d * bounds.top, d * bounds.bottom);
    aabb.min.setValues(
      _outward(min(ax0, ax1) + min(cy0, cy1) + tx, -1),
      _outward(min(bx0, bx1) + min(dy0, dy1) + ty, -1),
    );
    aabb.max.setValues(
      _outward(max(ax0, ax1) + max(cy0, cy1) + tx, 1),
      _outward(max(bx0, bx1) + max(dy0, dy1) + ty, 1),
    );
  }

  /// [v] moved by a few float32 steps in [direction], as points on a box's
  /// edges count as outside it.
  ///
  /// PathHitbox adds 1e-15 for the same reason. But the box's vectors are
  /// float32, which round that away at coordinates past about 1e-8.
  static double _outward(double v, double direction) =>
      v + direction * (v.abs() + 1) * 1e-6;
}

/// What the hitboxes of an outline share: its path rooted at the origin, and
/// its polygons for each of the last ways it was sampled.
class _Shared(SvgOutline outline) {
  /// What each outline's hitboxes share, kept as long as the outline is.
  static final _all = Expando<_Shared>();

  factory _Shared.of(SvgOutline outline) => _all[outline] ??= _Shared(outline);

  /// How many ways of sampling an outline keep their polygons, so that
  /// hitboxes made for ever new sizes don't keep ever more polygons.
  static const _kept = 8;

  /// The outline's path rooted at the origin.
  final Path path = outline.path.toOrigin;

  // Polygons by sampling, tolerance and filter, the most recently used last.
  final _sampled = <(double, double?, bool), _Polygons>{};

  /// The polygons sampled every [sampling], within [tolerance], with [filter]
  /// or not (see [PathComponent.new]).
  ///
  /// It makes them as PathComponent does, or returns the ones made earlier
  /// for the same values.
  _Polygons sampled(
    double sampling,
    double? tolerance, {
    required bool filter,
  }) {
    final key = (sampling, tolerance, filter);
    final kept = _sampled.remove(key);
    if (kept != null) {
      return _sampled[key] = kept;
    }
    if (_sampled.length == _kept) {
      _sampled.remove(_sampled.keys.first);
    }
    return _sampled[key] = _Polygons(
      path.toPolygons(sampling: sampling, tolerance: tolerance, filter: filter),
    );
  }
}

/// An outline's polygons sampled one way, and what its hitboxes derive from
/// them.
class _Polygons(
  /// The vertices of each polygon, in its hitboxes' coordinates.
  final List<List<Vector2>> vertices,
) {
  /// The [vertices], as [PathComponent.polygons].
  late final view = UnmodifiableListView([
    for (final polygon in vertices) UnmodifiableListView(polygon),
  ]);

  /// The polygons as one path, as in PathComponent.
  late final Path path = _pathOf(vertices);

  /// Their bounds, or null without polygons.
  late final Rect? bounds = _boundsOf(vertices);

  static Path _pathOf(List<List<Vector2>> polygons) {
    final path = Path();
    for (final polygon in polygons) {
      path.addPolygon(
        polygon.map((vertex) => vertex.toOffset()).toList(growable: false),
        true,
      );
    }
    return path;
  }

  static Rect? _boundsOf(Iterable<Iterable<Vector2>> polygons) {
    final vertices = polygons.expand((polygon) => polygon);
    if (vertices.isEmpty) {
      return null;
    }
    var (left, top) = (double.infinity, double.infinity);
    var (right, bottom) = (double.negativeInfinity, double.negativeInfinity);
    for (final vertex in vertices) {
      left = min(left, vertex.x);
      top = min(top, vertex.y);
      right = max(right, vertex.x);
      bottom = max(bottom, vertex.y);
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }
}
