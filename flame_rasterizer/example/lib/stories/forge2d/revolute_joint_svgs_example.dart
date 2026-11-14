import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame_forge2d/flame_forge2d.dart' hide World;
import 'package:flame_rasterizer/flame_rasterizer.dart';
import 'package:flame_rasterizer_example/commons/example_colors.dart';
import 'package:flame_rasterizer_example/commons/example_game.dart';
import 'package:flame_rasterizer_example/commons/forge2d.dart';
import 'package:flame_rasterizer_example/commons/svg_renderers.dart';
import 'package:flutter/foundation.dart';

part 'revolute_joint_svgs_snapshot.dart';

/// The values of the example's knobs, except Zoom, Speed and the cache knobs.
typedef RevoluteJointSvgsSettings = ({SvgRenderer renderer, bool pieces});

/// Flame's Forge2D revolute joint example, as flame_path_shapes extends it,
/// with SVGs: see [description].
///
/// Walls along the game's edges, at a zoom of 1, hold a wheel that a motor
/// turns, under a funnel of two ramps. Each tap drops [dropped] bodies: half
/// balls, and half SVGs from 3 to 3.5 meters at their larger side. The SVG
/// bodies draw above the others, so that flame_rasterizer draws them all in
/// one run of a [RasterizerCanvas]. [PiecesLayer] draws their convex pieces
/// over them while [pieces] is true.
///
/// The status adds the bodies dropped to [StoryGame]'s. As in
/// flame_path_shapes, the number of bodies at the top right counts the
/// walls, the ramps and the wheel too.
///
/// Given the snapshot of a game with another renderer, it goes on from there,
/// with the same bodies: see [RevoluteJointSvgsSnapshots].
abstract class RevoluteJointSvgsExample({
  required var bool pieces,
  required super.status,
  math.Random? random,
  RevoluteJointSvgsSnapshot? from,
}) extends Forge2DExampleGame with ExampleSvgs {
  this : super(world: RevoluteJointSvgsWorld());

  /// Creates the game for [settings]' renderer, with flame_svg's [cache] for
  /// Flame SVG, which goes on from [from], if any.
  factory RevoluteJointSvgsExample.of(
    RevoluteJointSvgsSettings settings,
    ValueNotifier<String> status, {
    SvgCache cache = defaultSvgCache,
    math.Random? random,
    RevoluteJointSvgsSnapshot? from,
  }) => settings.renderer == SvgRenderer.flameSvg
      ? FlameSvgRevoluteJointExample(
          pieces: settings.pieces,
          status: status,
          cache: cache,
          random: random,
          from: from,
        )
      : RasterizerRevoluteJointExample(
          pieces: settings.pieces,
          status: status,
          renderer: settings.renderer,
          random: random,
          from: from,
        );

  static const description = '''
    Flame's Forge2D revolute joint example, as flame_path_shapes extends it,
    with SVGs: a motor turns a wheel of five circles under a funnel. Each tap
    drops 15 bodies, half balls and half SVGs, which fall through the funnel
    into the wheel.

    The SVG bodies collide as the convex pieces of their outlines, which
    flame_rasterizer's SvgOutline gives, whatever draws the SVGs. They draw
    above the other bodies, so that flame_rasterizer draws them all together,
    in one run.

    The knobs pick the renderer, draw the convex pieces over the SVGs, zoom
    the camera and change the physics' speed. With Flame SVG, the cache knobs
    set flame_svg's cache. Only a new renderer or cache makes a new game. A
    new renderer's game goes on with the same bodies, from where they were.
    The frame rate is at the top left, and the number of bodies at the top
    right. The bar under the game shows the renderer, the frame times, the
    renderer's own numbers and the bodies dropped.

    Based on flame_path_shapes' RevoluteJointWithMotorExample.
  ''';

  /// How many bodies each tap drops.
  static const dropped = 15;

  /// The balls' smallest radius, in meters. Box2D works best with bodies
  /// from 0.1 to 10 meters.
  static const _minBallRadius = 0.4;

  /// The balls' largest radius, in meters.
  static const _maxBallRadius = 1.0;

  /// The larger side of the smallest SVGs, in meters.
  ///
  /// The SVGs come in [_sides] sizes, from 3 to 3.5 meters by tenths, as in
  /// flame_path_shapes. So each SVG's pieces are worked out once per size.
  static const _minSide = 3.0;

  /// How many sizes the SVGs come in.
  static const _sides = 6;

  /// The speed at which new bodies move away from the tap, in meters a
  /// second.
  static const _spreadSpeed = 2.0;

  final math.Random random = random ?? math.Random();

  /// The snapshot that it goes on from, if any.
  final RevoluteJointSvgsSnapshot? _from = from;

  /// The wheel, from [onLoad] on.
  CircleShuffler? _wheel;

  /// The SVG bodies dropped so far.
  final svgBodies = <SvgBody>[];

  /// The balls dropped so far.
  final balls = <Ball>[];

  /// The walls along the game's edges, at a zoom of 1.
  var _walls = <Wall>[];

  /// The SVGs of [randomSvgNames], loaded up front so that [drop] can be
  /// synchronous.
  final _svgs = <String, ExampleSvg>{};

  /// Each SVG's size and convex pieces, by its name and its size's index.
  final _pieces = <(String, int), (Vector2, List<List<Vector2>>)>{};

  /// The index of the next body's color: the bodies take the colors in turn.
  int _tint = 0;

  @override
  Iterable<String> get exampleStats {
    final ballCount = '${balls.length} ball${balls.length == 1 ? '' : 's'}';
    final svgCount =
        '${svgBodies.length} SVG${svgBodies.length == 1 ? '' : 's'}';
    return ['$ballCount, $svgCount'];
  }

  /// The world's rectangle that the game shows at a zoom of 1.
  Rect get _arena => Rect.fromCenter(
    center: Offset.zero,
    width: size.x / metersToPixels,
    height: size.y / metersToPixels,
  );

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    for (final name in randomSvgNames) {
      _svgs[name] = await loadSvg('assets/svgs/$name.svg');
      // The game was removed while it loaded, and its physics world is
      // destroyed.
      if (isRemoved) {
        return;
      }
    }
    final center = Vector2.zero();
    world.addAll([
      ...(_walls = Wall.around(_arena)),
      _wheel = CircleShuffler(center, from: _from?.wheel),
      CornerRamp(center, isMirrored: true),
      CornerRamp(center),
      PiecesLayer(),
    ]);
    _restoreBodies();
    startStatus();
  }

  /// Drops [dropped] bodies around [tap], a point in the world. They're
  /// spread out so that they don't overlap, and move away from [tap].
  void drop(Vector2 tap) {
    if (!isLoaded) {
      return;
    }
    // Half balls and half SVGs, alternating, each with its bounding radius
    // and a function that creates it.
    final ballsFirst = random.nextBool();
    final bodies = <(double, BodyComponent Function(Vector2, Vector2))>[
      for (var i = 0; i < dropped; i++)
        if (i.isEven == ballsFirst) _randomBall() else _randomSvg(),
    ];
    final positions = spreadAround(
      tap,
      [for (final (radius, _) in bodies) radius],
      bounds: _arena.deflate(Wall.width),
      world: world.physicsWorld,
      random: random,
    );
    for (final (i, (_, create)) in bodies.indexed) {
      final position = positions[i];
      final body = create(
        position,
        awayFrom(tap, position, _spreadSpeed, random),
      );
      switch (body) {
        case SvgBody():
          svgBodies.add(body);
        case Ball():
          balls.add(body);
      }
      world.add(body);
    }
  }

  /// Picks a ball of random radius, in the next color. Returns its radius,
  /// and a function that creates it with a position and a velocity.
  (double, BodyComponent Function(Vector2, Vector2)) _randomBall() {
    final radius =
        _minBallRadius +
        random.nextDouble() * (_maxBallRadius - _minBallRadius);
    final color = ExampleColors.dynamicColor(_tint++);
    return (
      radius,
      (position, velocity) =>
          Ball(position, velocity, radius: radius, color: color),
    );
  }

  /// Picks a random SVG, at a random size and angle, in the next color.
  /// Returns its bounding radius, and a function that creates its body with a
  /// position and a velocity.
  (double, BodyComponent Function(Vector2, Vector2)) _randomSvg() {
    final name = randomSvgNames[random.nextInt(randomSvgNames.length)];
    final side = random.nextInt(_sides);
    final (size, _) = _sizeAndPieces(name, side);
    final color = ExampleColors.dynamicColor(_tint++);
    final angle = random.nextDouble() * 2 * math.pi;
    return (
      size.length / 2,
      (position, velocity) =>
          _svgBody(name, side, position, velocity, angle: angle, color: color),
    );
  }

  /// Creates the body of the SVG [name] at its [side]th size, in [color],
  /// which starts at [position] and [angle], moving at [velocity], or goes on
  /// from [from], if any.
  SvgBody _svgBody(
    String name,
    int side,
    Vector2 position,
    Vector2 velocity, {
    required double angle,
    required Color color,
    BodySnapshot? from,
  }) {
    final (size, pieces) = _sizeAndPieces(name, side);
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
      from: from,
    );
  }

  /// The size and convex pieces of the SVG [name] at its [side]th size,
  /// worked out once.
  (Vector2, List<List<Vector2>>) _sizeAndPieces(String name, int side) =>
      _pieces[(name, side)] ??= () {
        final svg = _svgs[name]!;
        final s = (_minSide + side / 10) / math.max(svg.size.x, svg.size.y);
        final size = svg.size * s;
        return (size, convexPiecesOf(svg.outline, size));
      }();

  /// Moves the walls to the game's new edges, and removes the bodies they
  /// leave outside, which would fall forever.
  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    if (!isLoaded) {
      return;
    }
    final arena = _arena;
    world.removeAll(_walls);
    world.addAll(_walls = Wall.around(arena));
    bool outside(BodyComponent body) =>
        body.isLoaded && !arena.contains(body.body.position.toOffset());
    final gone = [...svgBodies.where(outside), ...balls.where(outside)];
    svgBodies.removeWhere(gone.contains);
    balls.removeWhere(gone.contains);
    world.removeAll(gone);
  }
}

/// The example's world, which drops bodies where it's tapped. Its HUD shows
/// the number of bodies, the fixed ones included.
class RevoluteJointSvgsWorld()
    extends Forge2DExampleWorld
    with TapCallbacks, HasGameRef<RevoluteJointSvgsExample>, BodiesHud {
  @override
  void onTapDown(TapDownEvent event) {
    super.onTapDown(event);
    gameRef.drop(event.localPosition);
  }
}

/// A body that draws [svg], [size] meters large and centered on it, and
/// collides as the SVG's convex [pieces].
///
/// It starts at [_position] and [_angle], moving at [_velocity], or goes on
/// from [from], if any, and draws above the other bodies. [PiecesLayer] draws
/// its pieces in [color].
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
  final BodySnapshot? from,
}) extends BodyComponent {
  this : super(renderBody: false, priority: 1);

  /// The [pieces] as one path, for [PiecesLayer].
  late final piecesPath = () {
    final path = Path();
    for (final piece in pieces) {
      path.addPolygon([for (final v in piece) v.toOffset()], true);
    }
    return path;
  }();

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    add(
      svg.component()
        ..size = size
        ..anchor = Anchor.center,
    );
  }

  @override
  Body createBody() {
    final body = world.createBody(
      BodyDef(
        type: BodyType.dynamic,
        position: _position,
        rotation: Rot.fromAngle(_angle),
        linearVelocity: _velocity,
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

/// Draws the SVG bodies' convex pieces over them, while the game's
/// [RevoluteJointSvgsExample.pieces] is true.
///
/// It draws after all the bodies, so that the SVGs stay in one run. A child
/// of each body, drawn over its SVG, would end the run at each body.
class PiecesLayer()
    extends Component
    with HasGameRef<RevoluteJointSvgsExample> {
  this : super(priority: 2);

  /// The width of the pieces' outlines, in meters, as in flame_path_shapes.
  static const _outlineWidth = 0.04;

  /// The paints for each body color.
  final _paints = <Color, GlowPaints>{};

  @override
  void render(Canvas canvas) {
    if (!gameRef.pieces) {
      return;
    }
    for (final svgBody in gameRef.svgBodies) {
      if (!svgBody.isLoaded) {
        continue;
      }
      final paints = _paints[svgBody.color] ??= GlowPaints(
        svgBody.color,
        _outlineWidth,
      );
      final position = svgBody.body.position;
      canvas
        ..save()
        ..translate(position.x, position.y)
        ..rotate(svgBody.angle)
        ..drawPath(svgBody.piecesPath, paints.fill)
        ..drawPath(svgBody.piecesPath, paints.outline)
        ..restore();
    }
  }
}

/// flame_path_shapes' wheel: five circles, 25 meters below [_center], that a
/// motor turns. It goes on from [from], if any.
class CircleShuffler(final Vector2 _center, {final BodySnapshot? from})
    extends BodyComponent {
  @override
  Body createBody() {
    const pieces = 5;
    const radius = 6.0;
    final body = world.createBody(
      BodyDef(type: BodyType.dynamic, position: _center + Vector2(0, 25)),
    );
    for (var i = 0; i < pieces; i++) {
      final angle = 2 * math.pi * i / pieces;
      body.createShape(
        Circle(
          radius: 1.2,
          center: Vector2(radius * math.cos(angle), radius * math.sin(angle)),
        ),
        ShapeDef(
          density: 50,
          material: SurfaceMaterial(friction: 0.5, restitution: 0.4),
        ),
      );
    }
    // The joint holds the wheel to an empty static body, as its ground.
    final ground = world.createBody(BodyDef());
    world.physicsWorld.createRevoluteJoint(
      RevoluteJointDef(
        bodyA: body,
        bodyB: ground,
        localAnchorB: body.position.clone(),
        motorSpeed: math.pi,
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

/// The example with flame_rasterizer: [RasterizerSvgComponent]s draw its
/// SVGs, with the renderer that the Renderer knob picks.
class RasterizerRevoluteJointExample({
  required super.pieces,
  required super.status,
  @override required final SvgRenderer renderer,
  super.random,
  super.from,
}) extends RevoluteJointSvgsExample
    with HasRasterizer, ExampleRasterizer, RasterizerSvgs {
  this {
    RasterizerGpu.forceCanvas = forceCanvas;
  }
}

/// The example with flame_svg: its `SvgComponent`s draw its SVGs as images,
/// cached as [cache] sets.
class FlameSvgRevoluteJointExample({
  required super.pieces,
  required super.status,
  final SvgCache cache = defaultSvgCache,
  super.random,
  super.from,
}) extends RevoluteJointSvgsExample with FlameSvgs {
  @override
  SvgCacheMode get cacheMode => cache.mode;

  @override
  SvgCacheSize get cacheSize => cache.size;
}
