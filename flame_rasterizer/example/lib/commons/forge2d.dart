import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/geometry.dart' show convexPieces;
import 'package:flame_forge2d/flame_forge2d.dart' as forge2d show World;
import 'package:flame_forge2d/flame_forge2d.dart' hide World;
import 'package:flame_rasterizer/flame_rasterizer.dart';
import 'package:flame_rasterizer_example/commons/example_colors.dart';
import 'package:flame_rasterizer_example/commons/example_game.dart';
import 'package:flutter/foundation.dart';

/// A Forge2D example's world, which runs at its game's
/// [Forge2DExampleGame.speed].
///
/// Its physics run at that speed too, as [Forge2DWorld.update] steps them by
/// the world's scaled time.
class Forge2DExampleWorld()
    extends Forge2DWorld
    with CustomTraversal, HasTimeScale;

/// Shows the number of a Forge2D world's bodies at the game's top right, as
/// in flame_path_shapes.
///
/// It counts all of the world's body components as they're added and
/// removed, those that don't move, such as the walls, included.
mixin BodiesHud on Forge2DWorld {
  var _bodyCount = 0;
  final _bodyCountText = _TopRightText();

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    // Like StoryGame's FPS text, it goes in the viewport, so that it's drawn
    // above the world and not zoomed.
    findGame()!.camera.viewport.add(_bodyCountText);
    _updateBodyCount();
  }

  @override
  void onChildrenChanged(Component child, ChildrenChangeType type) {
    super.onChildrenChanged(child, type);
    if (child is BodyComponent) {
      _bodyCount += type == ChildrenChangeType.added ? 1 : -1;
      _updateBodyCount();
    }
  }

  void _updateBodyCount() {
    _bodyCountText.text = 'Bodies: $_bodyCount';
  }
}

/// A text in StoryGame's style at the top right corner of its parent.
///
/// It stays there when the parent is resized.
class _TopRightText() extends TextComponent<TextPaint> {
  this
    : super(anchor: Anchor.topRight, textRenderer: StoryGame.hudTextRenderer);

  @override
  void onParentResize(Vector2 maxSize) {
    super.onParentResize(maxSize);
    position.setValues(maxSize.x - StoryGame.hudMargin, StoryGame.hudMargin);
  }
}

/// A Forge2D example's game, in [world], at 10 pixels a meter as in Flame's
/// examples, on [ExampleColors.background].
///
/// It destroys its physics world as it's removed. Box2D has room for only
/// 128 worlds at once, and removing a game from its widget doesn't remove
/// its bodies one by one.
abstract class Forge2DExampleGame({
  required Forge2DExampleWorld world,
  @override required final ValueNotifier<String> status,
}) extends Forge2DGame<Forge2DExampleWorld> with StoryGame {
  this : super(world: world, metersToPixels: 10);

  /// Whether Forge2D is initialized, so that the physics world exists and
  /// can be destroyed. On the web, Box2D's WebAssembly loads first.
  bool _initialized = false;

  @override
  double get speed => world.timeScale;

  @override
  set speed(double value) => world.timeScale = value;

  @override
  Color backgroundColor() => ExampleColors.background;

  @override
  @mustCallSuper
  Future<void> onLoad() async {
    await super.onLoad();
    _initialized = true;
  }

  @override
  void onRemove() {
    super.onRemove();
    if (_initialized) {
      world.physicsWorld.destroy();
    }
  }
}

/// The paints of Flame's Forge2D examples' bodies: a translucent fill of
/// [color], and a bright outline [outlineWidth] wide.
class GlowPaints(final Color color, final double outlineWidth) {
  late final fill = Paint()..color = color.withValues(alpha: 0.28);
  late final outline = Paint()
    ..color = color.withValues(alpha: 0.95)
    ..style = PaintingStyle.stroke
    ..strokeWidth = outlineWidth;
}

/// Draws a body's shapes with [GlowPaints] of its paint's color.
mixin GlowingBody on BodyComponent {
  /// The width of the outline, in meters.
  double get outlineWidth => 0.12;

  GlowPaints? _glow;

  /// The paints for its paint's color, made again when the color changes.
  GlowPaints get _paints {
    final glow = _glow;
    if (glow != null && glow.color == paint.color) {
      return glow;
    }
    return _glow = GlowPaints(paint.color, outlineWidth);
  }

  @override
  void renderCircle(Canvas canvas, Offset center, double radius) {
    final paints = _paints;
    canvas
      ..drawCircle(center, radius, paints.fill)
      ..drawCircle(center, radius, paints.outline)
      // A radius line shows the body turning.
      ..drawLine(center, center + Offset(radius, 0), paints.outline);
  }

  /// One path, reset for each polygon, as `BodyComponent` does.
  late final Path _path = Path();

  @override
  void renderPolygon(Canvas canvas, List<Offset> points) {
    final paints = _paints;
    final path = _path
      ..reset()
      ..addPolygon(points, true);
    canvas
      ..drawPath(path, paints.fill)
      ..drawPath(path, paints.outline);
  }

  @override
  void renderSegment(Canvas canvas, Offset p1, Offset p2) {
    canvas.drawLine(p1, p2, _paints.outline);
  }
}

/// A wall from [start] to [end], in meters.
class Wall(final Vector2 start, final Vector2 end)
    extends BodyComponent
    with GlowingBody {
  this : super(paint: Paint()..color = ExampleColors.slate);

  /// Its width as drawn, in meters.
  static const width = 0.15;

  /// Creates the walls along [rect]'s edges.
  static List<Wall> around(Rect rect) {
    final topLeft = Vector2(rect.left, rect.top);
    final topRight = Vector2(rect.right, rect.top);
    final bottomRight = Vector2(rect.right, rect.bottom);
    final bottomLeft = Vector2(rect.left, rect.bottom);
    return [
      Wall(topLeft, topRight),
      Wall(topRight, bottomRight),
      Wall(bottomLeft, bottomRight),
      Wall(topLeft, bottomLeft),
    ];
  }

  @override
  double get outlineWidth => width;

  /// Creates a fixed segment with the default material, whose friction lets
  /// bodies come to rest against the wall instead of sliding along it.
  @override
  Body createBody() =>
      world.createBody(BodyDef())
        ..createShape(Segment(point1: start, point2: end), ShapeDef());
}

/// A ball with a radius of [radius] meters, in `color`, which starts at
/// [_position], moving at [_velocity].
class Ball(
  final Vector2 _position,
  final Vector2 _velocity, {
  required final double radius,
  required Color color,
}) extends BodyComponent with GlowingBody {
  this : super(paint: Paint()..color = color);

  @override
  Body createBody() {
    final body = world.createBody(
      BodyDef(
        type: BodyType.dynamic,
        position: _position,
        linearVelocity: _velocity,
        angularDamping: 0.8,
      ),
    );
    body.createShape(
      Circle(radius: radius),
      ShapeDef(material: SurfaceMaterial(restitution: 0.7)),
    );
    return body;
  }
}

/// Box2D's linear slop, in meters, with the default length units.
///
/// It's the value of `Tolerances.linearSlop`, which needs the native
/// library. Box2D's `b2ComputeHull` welds a polygon's points closer than 4
/// times it, and drops points closer than twice it to an edge.
const linearSlop = 0.005;

/// The least length, in meters, of a convex piece's larger side.
///
/// flame_forge2d warns about smaller shapes: those under 5 times Box2D's
/// speculative distance, which is 4 times [linearSlop].
const minPieceSide = 5 * 4 * linearSlop;

/// Returns the convex pieces of [outline] at [size] meters, centered on it,
/// for Box2D to take as polygons.
///
/// It splits the polygons of the outline's [SvgHitbox], sampled every 0.1
/// meters, as a hitbox at 10 pixels a meter samples every pixel. It leaves
/// out the pieces under [minPieceSide] across, about a pixel at that scale.
List<List<Vector2>> convexPiecesOf(SvgOutline outline, Vector2 size) {
  final hitbox = SvgHitbox(outline, size: size, sampling: 0.1)..place(size);
  final half = size / 2;
  return [
    for (final polygon in hitbox.polygons)
      for (final piece in convexPieces(
        [for (final vertex in polygon) hitbox.positionOf(vertex) - half],
        minDistance: 4 * linearSlop,
        minWidth: 2 * linearSlop,
      ))
        if (pieceSide(piece) >= minPieceSide) piece,
  ];
}

/// The larger side of [piece]'s bounding box.
double pieceSide(List<Vector2> piece) {
  final xs = piece.map((v) => v.x);
  final ys = piece.map((v) => v.y);
  return math.max(
    xs.reduce(math.max) - xs.reduce(math.min),
    ys.reduce(math.max) - ys.reduce(math.min),
  );
}

/// Returns positions around [center] for new bodies whose bounding circles
/// have [radii].
///
/// The bodies overlap neither each other nor the shapes in [world], and lie
/// within [bounds]. From flame_path_shapes' `spreadAround`.
///
/// Box2D separates overlapping circles easily. Bodies made of several convex
/// pieces, as concave shapes are, can push each other in opposite directions
/// at once, and stay stuck together. So new bodies shouldn't start
/// overlapping.
///
/// It tries each position at random within a disc around [center], which
/// starts at [startRadius] and grows by [step] after each failed try. After
/// [maxTries] tries, it uses the last one anyway.
List<Vector2> spreadAround(
  Vector2 center,
  List<double> radii, {
  required Rect bounds,
  required forge2d.World world,
  required math.Random random,
  double startRadius = 1,
  double step = 0.1,
  int maxTries = 500,
}) {
  final placed = <(Vector2, double)>[];
  for (final radius in radii) {
    // Within the bounds, or at their center if the body doesn't fit.
    final inner = bounds.deflate(radius);
    final minX = inner.width > 0 ? inner.left : bounds.center.dx;
    final maxX = inner.width > 0 ? inner.right : bounds.center.dx;
    final minY = inner.height > 0 ? inner.top : bounds.center.dy;
    final maxY = inner.height > 0 ? inner.bottom : bounds.center.dy;
    var discRadius = startRadius;
    late Vector2 position;
    for (var tries = 0; tries < maxTries; tries++) {
      // A point uniformly distributed within the disc.
      final distance = discRadius * math.sqrt(random.nextDouble());
      final angle = random.nextDouble() * 2 * math.pi;
      position = Vector2(
        (center.x + distance * math.cos(angle)).clamp(minX, maxX),
        (center.y + distance * math.sin(angle)).clamp(minY, maxY),
      );
      final free =
          placed.every(
            (other) => other.$1.distanceTo(position) >= other.$2 + radius,
          ) &&
          !_overlapsWorld(world, position, radius);
      if (free) {
        break;
      }
      discRadius += step;
    }
    placed.add((position, radius));
  }
  return [for (final (position, _) in placed) position];
}

/// Returns a velocity of [speed] meters a second away from [from], for a
/// body at [position], or in a random direction if it's at [from].
///
/// So the bodies spread from a tap, as they would if they had started
/// overlapping.
Vector2 awayFrom(
  Vector2 from,
  Vector2 position,
  double speed,
  math.Random random,
) {
  final direction = position - from;
  final velocity = direction.isZero()
      ? Vector2(random.nextDouble() - 0.5, random.nextDouble() - 0.5)
      : direction;
  return velocity..scaleTo(speed);
}

/// Whether the circle at [center] of [radius] overlaps any shape in [world].
bool _overlapsWorld(forge2d.World world, Vector2 center, double radius) {
  final extent = Vector2.all(radius);
  final candidates = world.overlapAabb(Aabb(center - extent, center + extent));
  return candidates.any((shape) => _overlapsShape(shape, center, radius));
}

/// Whether the circle at [center] of [radius] overlaps [shape], whose
/// bounding box overlaps the circle's.
bool _overlapsShape(Shape shape, Vector2 center, double radius) {
  // The circle's center in the body's coordinates.
  final local = shape.body.localPoint(center);
  switch (shape.geometry) {
    case Circle(center: final c, radius: final r):
      return local.distanceTo(c) < radius + r;
    case Capsule(:final center1, :final center2, radius: final r):
      return _distanceToSegment(local, center1, center2) < radius + r;
    case Segment(:final point1, :final point2):
      return _distanceToSegment(local, point1, point2) < radius;
    case Polygon(:final points, radius: final r):
      if (points == null || points.length < 3) {
        // Without its points, the bounding box has to do.
        return true;
      }
      if (_contains(points, local)) {
        return true;
      }
      for (var i = 0; i < points.length; i++) {
        final a = points[i];
        final b = points[(i + 1) % points.length];
        if (_distanceToSegment(local, a, b) < radius + r) {
          return true;
        }
      }
      return false;
  }
}

/// Whether the convex [polygon] contains [point], whatever its winding.
bool _contains(List<Vector2> polygon, Vector2 point) {
  var sign = 0;
  for (var i = 0; i < polygon.length; i++) {
    final a = polygon[i];
    final b = polygon[(i + 1) % polygon.length];
    final side = (b - a).cross(point - a).sign.toInt();
    if (side == 0) {
      continue;
    }
    if (sign == 0) {
      sign = side;
    } else if (side != sign) {
      return false;
    }
  }
  return true;
}

/// The distance from [point] to the segment from [a] to [b].
double _distanceToSegment(Vector2 point, Vector2 a, Vector2 b) {
  final ab = b - a;
  final lengthSquared = ab.length2;
  if (lengthSquared == 0) {
    return point.distanceTo(a);
  }
  final t = ((point - a).dot(ab) / lengthSquared).clamp(0.0, 1.0);
  return point.distanceTo(a + ab * t);
}
