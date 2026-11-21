import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/extensions.dart';
import 'package:flame/geometry.dart' show convexPieces;
import 'package:flame_forge2d/flame_forge2d.dart' as forge2d show World;
import 'package:flame_forge2d/flame_forge2d.dart' hide World;
import 'package:flame_rasterizer/flame_rasterizer.dart';
import 'package:flame_rasterizer_example/commons/example_colors.dart';
import 'package:flame_rasterizer_example/commons/example_game.dart';
import 'package:flame_rasterizer_example/commons/svg_renderers.dart';
import 'package:flame_rasterizer_example/commons/vector_text_component.dart';
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

/// Draws a body's [glowPath] with [GlowPaints] of its paint's color, as a
/// child path component of the game's [PathComponents].
///
/// The paints are white, and the child is tinted with the color. So the
/// bodies that share a [glowPath] object share its import, whatever their
/// color. The body's own shapes aren't drawn.
mixin GlowingBody on BodyComponent {
  /// The width of the outline, in meters.
  double get outlineWidth => 0.12;

  /// The path to draw, in the body's coordinates: its shapes, by default.
  Path get glowPath => pathOf(body.shapes);

  /// The paint layers to draw [glowPath] with, in white.
  List<Paint> get glowLayers {
    final paints = GlowPaints(const Color(0xFFFFFFFF), outlineWidth);
    return [paints.fill, paints.outline];
  }

  /// Whether it draws [glowPath]: false for a body that its game draws
  /// otherwise.
  bool glows = true;

  PathComponent? _glow;

  /// The color it's tinted with.
  Color? _tint;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    renderBody = false;
    if (!glows) {
      return;
    }
    final path = glowPath;
    add(
      _glow =
          (findGame()! as PathComponents).pathComponent(
              path,
              Paint(),
              position: path.getBounds().topLeft.toVector2(),
            )
            ..paintLayers = glowLayers
            ..tint(_tint = paint.color),
    );
  }

  @override
  void update(double dt) {
    super.update(dt);
    final glow = _glow;
    if (glow != null && paint.color != _tint) {
      glow.tint(_tint = paint.color);
    }
  }

  /// Returns [shapes] as one path. A circle has a radius line that shows it
  /// turning, if [spokes].
  static Path pathOf(Iterable<Shape> shapes, {bool spokes = true}) {
    final path = Path();
    for (final shape in shapes) {
      switch (shape.geometry) {
        case Circle(:final center, :final radius):
          final c = center.toOffset();
          path.addOval(Rect.fromCircle(center: c, radius: radius));
          if (spokes) {
            path
              ..moveTo(c.dx, c.dy)
              ..lineTo(c.dx + radius, c.dy);
          }
        case Segment(:final point1, :final point2):
          path
            ..moveTo(point1.x, point1.y)
            ..lineTo(point2.x, point2.y);
        case Polygon(:final points):
          path.addPolygon([for (final v in points!) v.toOffset()], true);
        case Capsule():
          throw UnsupportedError('Capsules');
      }
    }
    return path;
  }
}

/// A wall from [start] to [end], in meters.
class Wall(final Vector2 start, final Vector2 end)
    extends BodyComponent
    with GlowingBody {
  this : super(paint: Paint()..color = ExampleColors.slate);

  /// Its width as drawn, in meters.
  static const width = 0.15;

  /// Its collision category, for a body to leave out of its mask so that it
  /// passes through the walls.
  static const category = 2;

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
  Body createBody() => world.createBody(BodyDef())
    ..createShape(
      Segment(point1: start, point2: end),
      ShapeDef(filter: Filter(categoryBits: category)),
    );
}

/// Where a body is and how it moves, for a body in a game with another
/// renderer to go on from.
typedef BodySnapshot = ({
  Vector2 position,
  Rot rotation,
  Vector2 linearVelocity,
  double angularVelocity,
  bool isAwake,
});

/// Takes a [Body]'s snapshot, and goes on from one.
extension BodySnapshots on Body {
  /// Where it is and how it moves.
  BodySnapshot get snapshot => (
    position: position.clone(),
    rotation: rotation,
    linearVelocity: linearVelocity.clone(),
    angularVelocity: angularVelocity,
    isAwake: isAwake,
  );

  /// Puts it where [from] was, moving as it was, if [from] is given.
  ///
  /// Call it after creating its shapes, before the physics' first step.
  /// Box2D's linear velocity is its center of mass's, which each new shape
  /// moves. So it would go on a little faster or slower if it spins.
  void goOnFrom(BodySnapshot? from) {
    if (from case final from?) {
      setTransform(from.position, from.rotation);
      linearVelocity = from.linearVelocity;
      angularVelocity = from.angularVelocity;
      isAwake = from.isAwake;
    }
  }
}

/// A ball with a radius of [radius] meters, in `color`, which starts at
/// [_position], moving at [_velocity], or goes on from [from], if any.
class Ball(
  final Vector2 _position,
  final Vector2 _velocity, {
  required final double radius,
  required Color color,
  final BodySnapshot? from,
}) extends BodyComponent with GlowingBody {
  this : super(paint: Paint()..color = color);

  /// The balls' paths, by radius, so that the balls of a size share one.
  static final _paths = <double, Path>{};

  @override
  Path get glowPath => _paths[radius] ??= super.glowPath;

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
    return body..goOnFrom(from);
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

/// Returns the larger side of [piece]'s bounding box.
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
  final placed = <({Vector2 position, double radius})>[];
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
            (other) =>
                other.position.distanceTo(position) >= other.radius + radius,
          ) &&
          !_overlapsWorld(world, position, radius);
      if (free) {
        break;
      }
      discRadius += step;
    }
    placed.add((position: position, radius: radius));
  }
  return [for (final (:position, radius: _) in placed) position];
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

/// Returns whether the circle at [center] of [radius] overlaps any shape in
/// [world].
bool _overlapsWorld(forge2d.World world, Vector2 center, double radius) {
  final extent = Vector2.all(radius);
  final candidates = world.overlapAabb(Aabb(center - extent, center + extent));
  return candidates.any((shape) => _overlapsShape(shape, center, radius));
}

/// Returns whether the circle at [center] of [radius] overlaps [shape], whose
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

/// Returns whether the convex [polygon] contains [point], whatever its winding.
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

/// Returns the distance from [point] to the segment from [a] to [b].
double _distanceToSegment(Vector2 point, Vector2 a, Vector2 b) {
  final ab = b - a;
  final lengthSquared = ab.length2;
  if (lengthSquared == 0) {
    return point.distanceTo(a);
  }
  final t = ((point - a).dot(ab) / lengthSquared).clamp(0.0, 1.0);
  return point.distanceTo(a + ab * t);
}

/// A body to drop: its bounding radius, and a function that creates it.
typedef NewBody = ({
  double radius,
  BodyComponent Function(Vector2 position, Vector2 velocity) create,
});

/// An SVG's size, and its convex pieces at that size, also as one path.
typedef _SizedPieces = ({
  Vector2 size,
  List<List<Vector2>> pieces,
  Path path,
});

/// A Forge2D example that drops balls, and SVG bodies from 3 to 3.5 meters at
/// their larger side. The SVGs' convex pieces draw over them while [pieces]
/// is true.
mixin SvgBodies on Forge2DExampleGame, ExampleSvgs<Forge2DExampleWorld> {
  /// The balls' smallest radius, in meters. Box2D works best with bodies
  /// from 0.1 to 10 meters.
  double get minBallRadius => 0.4;

  /// The balls' largest radius, in meters.
  static const _maxBallRadius = 1.0;

  /// How many radii the balls come in, evenly spaced, so that the balls of a
  /// radius share their path's import.
  static const _ballSizes = 6;

  /// The larger side of the smallest SVGs, in meters.
  ///
  /// The SVGs come in [_sides] sizes, from 3 to 3.5 meters by tenths, as in
  /// flame_path_shapes. So [_sizeAndPieces] works out each SVG's pieces once
  /// per size.
  static const _minSide = 3.0;

  /// How many sizes the SVGs come in.
  static const _sides = 6;

  /// The larger side of the largest SVGs, in meters.
  static const maxSide = _minSide + (_sides - 1) / 10;

  math.Random get random;

  /// Whether the SVG bodies' convex pieces draw over them.
  bool get pieces;

  /// The paints of the convex pieces, in white, as each body tints them with
  /// its color. The outline is 0.04 meters wide, as in flame_path_shapes.
  static final _piecesPaints = GlowPaints(const Color(0xFFFFFFFF), 0.04);

  /// The SVG bodies dropped so far.
  final svgBodies = <SvgBody>[];

  /// The balls dropped so far.
  final balls = <Ball>[];

  /// The SVGs of [randomSvgNames], loaded up front so that dropping can be
  /// synchronous.
  final _svgs = <String, ExampleSvg>{};

  /// Each SVG's size and convex pieces, by its name and its size's index.
  final _pieces = <({String name, int side}), _SizedPieces>{};

  /// The index of the next body's color: the bodies take the colors in turn.
  int tint = 0;

  @override
  Iterable<String> get exampleStats {
    final ballCount = '${balls.length} ball${balls.length == 1 ? '' : 's'}';
    final svgCount =
        '${svgBodies.length} SVG${svgBodies.length == 1 ? '' : 's'}';
    return ['$ballCount, $svgCount'];
  }

  /// Loads the SVGs of [randomSvgNames]. Returns false if the game was removed
  /// while they loaded, and its physics world is destroyed.
  Future<bool> loadBodySvgs() async {
    for (final name in randomSvgNames) {
      _svgs[name] = await loadSvg('assets/svgs/$name.svg');
      if (isRemoved) {
        return false;
      }
    }
    return true;
  }

  /// Adds [body] to the world, and to [svgBodies] or [balls].
  void addBody(BodyComponent body) {
    switch (body) {
      case SvgBody():
        svgBodies.add(body);
      case Ball():
        balls.add(body);
    }
    world.add(body);
  }

  /// Removes [bodies] from the world, and from [svgBodies] and [balls].
  void removeBodies(List<BodyComponent> bodies) {
    svgBodies.removeWhere(bodies.contains);
    balls.removeWhere(bodies.contains);
    world.removeAll(bodies);
  }

  /// Returns the next body's color, a ball's or the SVG [svg]'s: the next of
  /// [ExampleColors.dynamics].
  Color nextColor([String? svg]) => ExampleColors.dynamicColor(tint++);

  /// Creates the component that draws [body]'s SVG, centered on it.
  ///
  /// It's sized in pixels and scaled back to meters, as flame_svg's fixed
  /// cache mode rasterizes an SVG at its component's size, without the
  /// camera's.
  PositionComponent svgImage(SvgBody body) => body.svg.component()
    ..size = body.size * metersToPixels
    ..scale = Vector2.all(1 / metersToPixels)
    ..anchor = Anchor.center;

  /// Creates the component that draws [body]'s convex pieces over its SVG.
  /// The bodies of an SVG's size share its path's import.
  PathComponent piecesOutline(SvgBody body) {
    final (size: _, pieces: _, :path) = _sizeAndPieces(body.name, body.side);
    return (this as PathComponents).pathComponent(
        path,
        Paint(),
        position: path.getBounds().topLeft.toVector2(),
        priority: 1,
      )
      ..paintLayers = [_piecesPaints.fill, _piecesPaints.outline]
      ..tint(body.color);
  }

  /// Picks a ball of random radius, in the next color. Returns its radius,
  /// and a function that creates it with a position and a velocity.
  NewBody randomBall() {
    final radius =
        minBallRadius +
        random.nextInt(_ballSizes) *
            (_maxBallRadius - minBallRadius) /
            (_ballSizes - 1);
    final color = nextColor();
    return (
      radius: radius,
      create: (position, velocity) =>
          Ball(position, velocity, radius: radius, color: color),
    );
  }

  /// Picks a random SVG, at a random size and angle, spinning at up to [spin]
  /// radians a second, in the next color. Returns its bounding radius, and a
  /// function that creates its body with a position and a velocity.
  NewBody randomSvg({double spin = 0}) {
    final name = randomSvgNames[random.nextInt(randomSvgNames.length)];
    final side = random.nextInt(_sides);
    final (:size, pieces: _, path: _) = _sizeAndPieces(name, side);
    final color = nextColor(name);
    final angle = random.nextDouble() * 2 * math.pi;
    final angularVelocity = (2 * random.nextDouble() - 1) * spin;
    return (
      radius: size.length / 2,
      create: (position, velocity) => createSvgBody(
        name,
        side,
        position,
        velocity,
        angle: angle,
        angularVelocity: angularVelocity,
        color: color,
      ),
    );
  }

  /// Creates the body of the SVG [name] at its [side]th size, in [color],
  /// which starts at [position] and [angle], moving at [velocity] and
  /// [angularVelocity], or goes on from [from], if any.
  SvgBody createSvgBody(
    String name,
    int side,
    Vector2 position,
    Vector2 velocity, {
    required double angle,
    required Color color,
    double angularVelocity = 0,
    BodySnapshot? from,
  }) {
    final (:size, :pieces, path: _) = _sizeAndPieces(name, side);
    return SvgBody(
      _svgs[name]!,
      size,
      pieces,
      position,
      velocity,
      angle: angle,
      color: color,
      name: name,
      side: side,
      angularVelocity: angularVelocity,
      from: from,
    );
  }

  /// Returns the size and convex pieces of the SVG [name] at its [side]th size,
  /// worked out once.
  _SizedPieces _sizeAndPieces(
    String name,
    int side,
  ) => _pieces[(name: name, side: side)] ??= () {
    final svg = _svgs[name]!;
    final s = (_minSide + side / 10) / math.max(svg.size.x, svg.size.y);
    final size = svg.size * s;
    final pieces = convexPiecesOf(svg.outline, size);
    final path = Path();
    for (final piece in pieces) {
      path.addPolygon([for (final v in piece) v.toOffset()], true);
    }
    return (size: size, pieces: pieces, path: path);
  }();
}

/// A body that draws [svg], [size] meters large and centered on it, and
/// collides as the SVG's convex [pieces].
///
/// It starts at [_position] and [_angle], moving at [_velocity], or goes on
/// from [from], if any, and draws above the other bodies. Its pieces draw over
/// it in [color] while the game's [SvgBodies.pieces] is true.
class SvgBody(
  final ExampleSvg svg,
  final Vector2 size,
  final List<List<Vector2>> pieces,
  final Vector2 _position,
  final Vector2 _velocity, {
  required final double _angle,
  required final Color color,

  /// The SVG's name, for a game with another renderer to load it.
  required final String name,

  /// The index of the SVG's size, for a game with another renderer.
  required final int side,
  final double _angularVelocity = 0,
  final BodySnapshot? from,
}) extends BodyComponent {
  this : super(renderBody: false, priority: 1);

  /// The component that draws its pieces, while the game shows them.
  PathComponent? _piecesOutline;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    add((gameRef as SvgBodies).svgImage(this));
  }

  @override
  void update(double dt) {
    super.update(dt);
    final game = gameRef as SvgBodies;
    if (game.pieces == (_piecesOutline != null)) {
      return;
    }
    if (_piecesOutline case final outline?) {
      outline.removeFromParent();
      _piecesOutline = null;
    } else {
      add(_piecesOutline = game.piecesOutline(this));
    }
  }

  @override
  Body createBody() {
    final body = world.createBody(
      BodyDef(
        type: BodyType.dynamic,
        position: _position,
        rotation: Rot.fromAngle(_angle),
        linearVelocity: _velocity,
        angularVelocity: _angularVelocity,
      ),
    );
    final shapeDef = ShapeDef(
      material: SurfaceMaterial(restitution: 0.4, friction: 0.5),
    );
    for (final piece in pieces) {
      body.createShape(Polygon(piece), shapeDef);
    }
    return body..goOnFrom(from);
  }
}

/// flame_path_shapes' wheel: five circles around [_position] that a motor
/// turns, [scale] times as large. It's filled, or drawn as the other glowing
/// bodies in [color], if given. It goes on from [from], if any.
///
/// It passes through the walls, which a short game brings into its way.
class CircleShuffler(
  final Vector2 _position, {
  final BodySnapshot? from,
  final double scale = 1,
  final Color? color,
}) extends BodyComponent with GlowingBody {
  this : super(paint: color == null ? null : (Paint()..color = color));

  @override
  Path get glowPath => GlowingBody.pathOf(body.shapes, spokes: false);

  @override
  List<Paint> get glowLayers => color == null
      ? [Paint()..color = const Color(0xFFFFFFFF)]
      : super.glowLayers;

  /// The distance of the circles' centers from the wheel's, in meters.
  static const _radius = 6.0;

  /// The circles' radius, in meters.
  static const _circleRadius = 1.2;

  /// How far the wheel reaches from its center, in meters.
  static const reach = _radius + _circleRadius;

  /// The motor's speed, in radians a second.
  static const _speed = math.pi;

  /// How long the motor takes to turn the other way, in seconds.
  static const _reverseTime = 1.0;

  late final RevoluteJoint _joint;

  /// The speed that the motor heads for.
  double _targetSpeed = _speed;

  /// The motor's speed, kept here: Box2D's is a float, which never equals
  /// [_targetSpeed].
  double _motorSpeed = _speed;

  /// Its color, and the one it takes while [reversing].
  late final _color = paint.color;
  static final _reversingColor = ExampleColors.dynamicColor(2);

  /// Slows the wheel down, then turns it the other way.
  void reverse() => _targetSpeed = -_targetSpeed;

  /// Whether it's turning the other way after [reverse], until it's at full
  /// speed.
  bool get reversing => _motorSpeed != _targetSpeed;

  @override
  void update(double dt) {
    super.update(dt);
    final speed = _motorSpeed;
    if (speed != _targetSpeed) {
      final step = 2 * _speed * dt / _reverseTime;
      _joint.motorSpeed = _motorSpeed = (_targetSpeed - speed).abs() <= step
          ? _targetSpeed
          : speed + step * (_targetSpeed - speed).sign;
    }
    paint.color = reversing ? _reversingColor : _color;
  }

  @override
  Body createBody() {
    const pieces = 5;
    final body = world.createBody(
      BodyDef(type: BodyType.dynamic, position: _position),
    );
    final shapeDef = ShapeDef(
      density: 50,
      material: SurfaceMaterial(friction: 0.4, restitution: 0.6),
      filter: Filter(maskBits: Filter.allCategories & ~Wall.category),
    );
    for (var i = 0; i < pieces; i++) {
      final angle = 2 * math.pi * i / pieces;
      body.createShape(
        Circle(
          radius: _circleRadius * scale,
          center: Vector2(math.cos(angle), math.sin(angle))
            ..scale(_radius * scale),
        ),
        shapeDef,
      );
    }
    // The joint holds the wheel to an empty static body, as its ground.
    final ground = world.createBody(BodyDef());
    _joint = world.physicsWorld.createRevoluteJoint(
      RevoluteJointDef(
        bodyA: body,
        bodyB: ground,
        localAnchorB: body.position.clone(),
        motorSpeed: _speed,
        maxMotorTorque: 1000000,
        enableMotor: true,
      ),
    );
    return body..goOnFrom(from);
  }
}

/// One of the two ramps of flame_path_shapes' funnel above the wheel. It's on
/// the right of [_center], or on the left if [isMirrored].
class CornerRamp(final Vector2 _center, {final bool isMirrored = false})
    extends BodyComponent
    with GlowingBody {
  this : super(paint: Paint()..color = ExampleColors.slate);

  @override
  Body createBody() {
    final mirror = isMirrored ? -1 : 1;
    // The two tips are 12 meters apart: about three and a half SVGs, and a
    // little less than the wheel's 14.4 meters. At 8 meters, SVGs dropped
    // above the opening sometimes clogged it.
    final tip = 6.0 * mirror;
    // A solid polygon, not a chain loop. Chains are one-sided in Box2D v3, so
    // a chain ramp would let balls in from the other side and trap them.
    return world.createBody(BodyDef(position: _center))..createShape(
      Polygon([
        Vector2(tip, 0),
        Vector2(tip + 20 * mirror, -20),
        Vector2(tip + 35 * mirror, -30),
      ]),
      ShapeDef(material: SurfaceMaterial(friction: 0.5)),
    );
  }
}
