import 'dart:math' as math;

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flame_rasterizer/flame_rasterizer.dart';
import 'package:flame_rasterizer_example/commons/example_game.dart';
import 'package:flame_rasterizer_example/commons/svg_renderers.dart';
import 'package:flutter/widgets.dart';

part 'collidable_svgs_snapshot.dart';

/// The values of the example's knobs, except Zoom, Speed and the cache knobs.
typedef CollidableSvgsSettings = ({SvgRenderer renderer, int count});

/// SVGs that move, spin, and bounce off each other and the walls: see
/// [description].
///
/// The walls are an [arena] of the game's size, centred on the world's
/// origin. The status adds the collisions so far to [ExampleGame]'s.
/// Subclasses pick what loads and draws the SVGs: see [ExampleSvgs].
///
/// Given the snapshot of a game with another renderer, it goes on from there,
/// with the same SVGs: see [CollidableSvgsSnapshots].
abstract class CollidableSvgsExample({
  required var int _count,
  required super.status,
  math.Random? random,
  CollidableSvgsSnapshot? from,
}) extends ExampleGame with ExampleSvgs, HasCollisionDetection {
  /// Creates the game for [settings]' renderer, with flame_svg's [cache] for
  /// Flame SVG, which goes on from [from], if any.
  factory CollidableSvgsExample.of(
    CollidableSvgsSettings settings,
    ValueNotifier<String> status, {
    SvgCache cache = defaultSvgCache,
    math.Random? random,
    CollidableSvgsSnapshot? from,
  }) => settings.renderer == SvgRenderer.flameSvg
      ? FlameSvgCollidableExample(
          count: settings.count,
          status: status,
          cache: cache,
          random: random,
          from: from,
        )
      : RasterizerCollidableExample(
          count: settings.count,
          status: status,
          renderer: settings.renderer,
          random: random,
          from: from,
        );

  static const description = '''
    SVGs picked at random move and spin, like the birds of Flame's animated
    collision example. Their hitboxes follow the contours of their paths:
    they're flame_rasterizer's SvgHitbox, whatever draws the SVGs. Two SVGs
    that collide swap their velocities, and an SVG that hits a wall turns
    back.

    The knobs pick the renderer and the SVG number, zoom the camera and change
    the SVGs' speed. With Flame SVG, the cache knobs set flame_svg's cache.
    Only a new renderer or cache makes a new game. A new renderer's game goes
    on with the same SVGs, from where they were. The bar under the game shows
    the renderer, the frame times, the renderer's own numbers and the
    collisions so far.

    Based on flame_path_shapes' CollidableSvgPathsExample.
  ''';

  /// The widths that an SVG gets at random, as in flame_path_shapes. [_fit]
  /// shrinks them when there are many SVGs.
  static const _widths = [150 / 3, 150 / 2, 150 * 2 / 3, 150.0];

  /// The slowest speed, in world units a second.
  static const _minSpeed = 140.0;

  /// The fastest speed, in world units a second.
  static const _maxSpeed = 420.0;

  /// The most of the arena's area that the SVGs' rectangles cover.
  static const _cover = 0.25;

  final math.Random random = random ?? math.Random();

  /// The snapshot that it goes on from, if any.
  final CollidableSvgsSnapshot? _from = from;

  /// The SVG Number knob's value. A new value changes the running game: it
  /// adds SVGs where there's room, or removes the last ones, and shrinks them
  /// all again to fit.
  int get count => _count;
  set count(int value) {
    if (value == _count) {
      return;
    }
    _count = value;
    if (_started) {
      _apply();
    }
  }

  /// The arena, whose walls the SVGs bounce off.
  late final CollidableArena arena;

  /// The SVGs, once loaded.
  final svgs = <CollidableSvg>[];

  /// The number of collisions between SVGs so far.
  int collisions = 0;

  /// The names of its SVGs, at least as many as it has had. They go through
  /// all the names in a random order, then again in another, and so on.
  final _names = <String>[];

  /// The widths picked for its SVGs, before [_fit] shrinks them.
  final _widthsPicked = <double>[];

  /// The SVGs loaded so far, by name.
  final _loaded = <String, ExampleSvg>{};

  /// Whether [onLoad] has run.
  bool _started = false;

  /// Whether [_apply] is running, so that another call leaves the work to it.
  bool _applying = false;

  @override
  Iterable<String> get exampleStats => [
    '$collisions collision${collisions == 1 ? '' : 's'}',
  ];

  @override
  Future<void> onLoad() async {
    _started = true;
    _restorePicks();
    arena = CollidableArena(size: size.clone());
    world.add(arena);
    await _apply();
    _restoreSvgs();
    startStatus();
  }

  /// Gives it [count] SVGs, loading those it lacks.
  ///
  /// It goes on until it has [count], as [count] can change while SVGs load.
  Future<void> _apply() async {
    if (_applying) {
      return;
    }
    _applying = true;
    try {
      while (!isRemoved && svgs.length != _count) {
        final target = _count;
        while (_names.length < target) {
          _names.addAll([...randomSvgNames]..shuffle(random));
        }
        for (final name in _names.take(target)) {
          _loaded[name] ??= await loadSvg('assets/svgs/$name.svg');
        }
        if (!isRemoved && _count == target) {
          _fit(target);
        }
      }
    } finally {
      _applying = false;
    }
  }

  /// Keeps its first [target] SVGs and adds new ones where there's room,
  /// shrinking them all so that they cover at most [_cover] of the arena.
  void _fit(int target) {
    while (_widthsPicked.length < target) {
      _widthsPicked.add(_widths[random.nextInt(_widths.length)]);
    }
    final svgSizes = [
      for (var i = 0; i < target; i++)
        Vector2(
          _widthsPicked[i],
          _widthsPicked[i] *
              _loaded[_names[i]]!.size.y /
              _loaded[_names[i]]!.size.x,
        ),
    ];
    final area = svgSizes.fold(0.0, (a, s) => a + s.x * s.y);
    final shrink = math.min(1, math.sqrt(_cover * size.x * size.y / area));
    for (final svgSize in svgSizes) {
      svgSize.scale(shrink.toDouble());
    }
    if (svgs.length > target) {
      world.removeAll(svgs.sublist(target));
      svgs.length = target;
    }
    for (final (i, svg) in svgs.indexed) {
      svg.resize(svgSizes[i]);
    }
    for (var i = svgs.length; i < target; i++) {
      final svg = CollidableSvg(
        _loaded[_names[i]]!,
        arena: arena,
        size: svgSizes[i],
        velocity: Vector2(
          _minSpeed + random.nextDouble() * (_maxSpeed - _minSpeed),
          0,
        )..rotate(random.nextDouble() * math.pi * 2),
        angle: random.nextDouble() * math.pi * 2,
      )..position = arena.freePosition(svgSizes[i], svgs, random);
      svgs.add(svg);
      world.add(svg);
    }
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    // The arena exists from onLoad on, before the SVGs load.
    if (!_started) {
      return;
    }
    arena.size = size.clone();
    // Bring back in the SVGs that the new size left outside.
    final rect = arena.toRect();
    for (final svg in svgs) {
      svg.position.setValues(
        svg.position.x.clamp(rect.left, rect.right),
        svg.position.y.clamp(rect.top, rect.bottom),
      );
    }
  }
}

/// The walls that the SVGs bounce off: a rectangle of the game's size,
/// centred on the world's origin, which the camera looks at.
class CollidableArena({required super.size}) extends PositionComponent {
  this : super(anchor: Anchor.center);

  @override
  Future<void> onLoad() async {
    add(RectangleHitbox(collisionType: CollisionType.passive));
  }

  /// Returns a center in the arena for a component of [size], whose circle
  /// overlaps none of [others]' circles.
  ///
  /// It tries 100 centers from [random], and returns the last one if none
  /// fits.
  Vector2 freePosition(
    Vector2 size,
    Iterable<PositionComponent> others,
    math.Random random,
  ) {
    final radius = size.length / 2;
    final rect = toRect();
    final position = Vector2.zero();
    for (var tries = 0; tries < 100; tries++) {
      position.setValues(
        rect.left + radius + random.nextDouble() * (rect.width - 2 * radius),
        rect.top + radius + random.nextDouble() * (rect.height - 2 * radius),
      );
      if (others.every(
        (other) =>
            other.absoluteCenter.distanceTo(position) >
            radius + other.size.length / 2,
      )) {
        break;
      }
    }
    return position;
  }
}

/// An SVG that moves with [velocity] and spins, with an [SvgHitbox] in its
/// shape.
///
/// When it collides with another, the two swap their velocities. When it
/// hits the walls of [arena], it turns back.
class CollidableSvg(
  final ExampleSvg svg, {
  required final CollidableArena arena,
  required Vector2 size,
  required final Vector2 velocity,
  super.angle,
}) extends PositionComponent with CollisionCallbacks {
  this : super(size: size, anchor: Anchor.center);

  /// Seconds per turn, as in flame_path_shapes.
  static const _turnTime = 3.0;

  /// The component that draws the SVG.
  late final _image = svg.component();

  @override
  Future<void> onLoad() async {
    addAll([
      _image..size = size,
      SvgHitbox(svg.outline, size: size),
      RotateEffect.by(
        math.pi * 2,
        EffectController(duration: _turnTime, infinite: true),
      ),
    ]);
  }

  /// Resizes it, and its SVG, to [value]. Its hitbox follows its size.
  void resize(Vector2 value) {
    size = value;
    _image.size = value;
  }

  @override
  void update(double dt) {
    super.update(dt);
    position.addScaled(velocity, dt);
    _comeBack();
  }

  /// Brings it back to any wall of the arena that its center went past,
  /// moving away from it.
  ///
  /// Flame checks collisions once a frame, after the moves. On a long frame,
  /// a small and fast SVG can cross a wall without touching it.
  void _comeBack() {
    final rect = arena.toRect();
    if (position.x < rect.left) {
      position.x = rect.left;
      velocity.x = velocity.x.abs();
    } else if (position.x > rect.right) {
      position.x = rect.right;
      velocity.x = -velocity.x.abs();
    }
    if (position.y < rect.top) {
      position.y = rect.top;
      velocity.y = velocity.y.abs();
    } else if (position.y > rect.bottom) {
      position.y = rect.bottom;
      velocity.y = -velocity.y.abs();
    }
  }

  @override
  void onCollisionStart(
    List<Vector2> intersectionPoints,
    PositionComponent other,
  ) {
    super.onCollisionStart(intersectionPoints, other);
    if (other is CollidableSvg) {
      _bounceOff(other);
    }
  }

  /// Bounces off the walls at every frame that it touches them, not only as
  /// it starts to.
  ///
  /// Another SVG can send it back toward the walls while it still touches
  /// them. With no new contact, it would then leave the arena.
  @override
  void onCollision(List<Vector2> intersectionPoints, PositionComponent other) {
    super.onCollision(intersectionPoints, other);
    if (other is CollidableArena) {
      _bounceOffWalls(other, intersectionPoints);
    }
  }

  /// Swaps velocities with [other], as in an elastic collision of two bodies
  /// of the same mass, and counts the collision.
  ///
  /// A collision calls it once for each of the two SVGs. At the second call,
  /// they're moving apart already, so it does nothing.
  void _bounceOff(CollidableSvg other) {
    final relativeVelocity = velocity - other.velocity;
    final towardsOther = other.absoluteCenter - absoluteCenter;
    if (relativeVelocity.dot(towardsOther) <= 0) {
      return;
    }
    final previous = velocity.clone();
    velocity.setFrom(other.velocity);
    other.velocity.setFrom(previous);
    final game = findGame();
    if (game is CollidableSvgsExample) {
      game.collisions++;
    }
  }

  /// Reflects off the walls of [arena] that [intersectionPoints] are on, as a
  /// mirror would.
  ///
  /// Only the velocity's component across a wall turns, and only if it points
  /// into the wall. A spinning SVG's corner can touch a wall again right
  /// after a bounce, or another SVG can have sent it away already. In a
  /// corner of the arena, turning the whole velocity would send it into the
  /// other wall.
  void _bounceOffWalls(
    CollidableArena arena,
    List<Vector2> intersectionPoints,
  ) {
    final rect = arena.toRect();
    for (final point in intersectionPoints) {
      if (point.x <= rect.left + 1) {
        velocity.x = velocity.x.abs();
      } else if (point.x >= rect.right - 1) {
        velocity.x = -velocity.x.abs();
      }
      if (point.y <= rect.top + 1) {
        velocity.y = velocity.y.abs();
      } else if (point.y >= rect.bottom - 1) {
        velocity.y = -velocity.y.abs();
      }
    }
  }
}

/// The example with flame_rasterizer: [RasterizerSvgComponent]s draw its
/// SVGs, with the renderer that the Renderer knob picks.
class RasterizerCollidableExample({
  required super.count,
  required super.status,
  @override required final SvgRenderer renderer,
  super.random,
  super.from,
}) extends CollidableSvgsExample
    with HasRasterizer, ExampleRasterizer, RasterizerSvgs {
  this {
    RasterizerGpu.forceCanvas = forceCanvas;
  }
}

/// The example with flame_svg: its `SvgComponent`s draw its SVGs as images,
/// cached as [cache] sets.
class FlameSvgCollidableExample({
  required super.count,
  required super.status,
  final SvgCache cache = defaultSvgCache,
  super.random,
  super.from,
}) extends CollidableSvgsExample with FlameSvgs {
  @override
  SvgCacheMode get cacheMode => cache.mode;

  @override
  SvgCacheSize get cacheSize => cache.size;
}
