import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flame/events.dart';
import 'package:flame/geometry.dart' show convexPieces;
import 'package:flame_forge2d/flame_forge2d.dart' hide World;
import 'package:flame_rasterizer/flame_rasterizer.dart';
import 'package:flame_rasterizer_example/commons/example_colors.dart';
import 'package:flame_rasterizer_example/commons/forge2d.dart';
import 'package:flame_rasterizer_example/commons/svg_renderers.dart';
import 'package:flame_rasterizer_example/commons/vector_text_component.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show KeyEventResult;

abstract class RevolutePinballExample({
  @override required var bool pieces,
  required super.status,
}) extends Forge2DExampleGame
    with
        ExampleSvgs,
        SvgBodies,
        KeyboardEvents,
        PathComponents<Forge2DExampleWorld> {
  this : super(world: RevolutePinballWorld());

  factory RevolutePinballExample.of(
    SvgRenderer renderer,
    ValueNotifier<String> status, {
    required bool pieces,
    SvgCache cache = defaultSvgCache,
  }) => renderer == SvgRenderer.flameSvg
      ? FlameSvgRevolutePinballExample(
          pieces: pieces,
          status: status,
          cache: cache,
        )
      : RasterizerRevolutePinballExample(
          pieces: pieces,
          status: status,
          renderer: renderer,
        );

  static const description = '''
    A pinball with the bodies of Revolute Joint Svgs. A key or a tap starts
    it, and drops 20 bodies over a wheel. The next 20 drop once each is in a
    bucket, gone through the drain, or at rest. Left or A, Right or D, or a
    tap in the bottom third's left or right half flips a flipper. Fill both
    buckets.
  ''';

  static final _flipperKeys = {
    LogicalKeyboardKey.arrowLeft: 0,
    LogicalKeyboardKey.keyA: 0,
    LogicalKeyboardKey.arrowRight: 1,
    LogicalKeyboardKey.keyD: 1,
  };

  static const _dropped = 20;
  static const _maxBodies = 100;

  /// The room left above a bucket's resting bodies, in meters, under which
  /// it's full.
  static const _fullRoom = SvgBodies.maxSide / 2;

  /// How long a body below [_restSpeed] stays so to be at rest, in seconds.
  static const _restTime = 0.5;
  static const _restSpeed = 0.5;

  /// The flippers' angle at rest, and the guides' slope.
  static const _restAngle = math.pi / 6;

  @override
  final random = math.Random();

  _Table? _table;
  var _flippers = <_Flipper>[];
  var _buckets = <_Bucket>[];
  final _ready = VectorTextComponent(
    text: 'READY',
    capHeight: VectorTextComponent.maxCapHeight,
  );

  /// The last bodies dropped, with how long each has been at rest.
  var _current = <BodyComponent, double>{};

  String get _bucketCounts =>
      _buckets.map((b) => '${b.count}${b.full ? ' full' : ''}').join(' · ');

  @override
  Iterable<String> get exampleStats => [
    ...super.exampleStats,
    'buckets $_bucketCounts',
  ];

  Rect get _arena => Rect.fromCenter(
    center: Offset.zero,
    width: size.x / metersToPixels,
    height: size.y / metersToPixels,
  );

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    if (!await loadBodySvgs()) {
      return;
    }
    world.add(PiecesLayer());
    camera.viewport.add(_ready);
    _buildTable();
    startStatus();
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    if (isLoaded) {
      _buildTable();
    }
  }

  /// Rebuilds the walls, the guides, the flippers, the wheel and the buckets
  /// for the arena's size.
  void _buildTable() {
    final a = _arena;
    final drain = math.max(0.06 * a.width, SvgBodies.maxSide);
    final flipper = 0.18 * a.width;
    final small = math.min(a.width, a.height);
    final pivot = Vector2(
      drain + flipper * math.cos(_restAngle),
      a.bottom - flipper * math.sin(_restAngle),
    );
    final guideTop = a.bottom - (a.right - drain) * math.tan(_restAngle);
    final bucketWidth = math.max(0.2 * a.width, 2 * SvgBodies.maxSide);
    final bucketHeight = 0.2 * small;
    final table = _Table([
      Wall(Vector2(a.left, a.top), Vector2(a.right, a.top)),
      Wall(Vector2(a.left, a.top), Vector2(a.left, a.bottom)),
      Wall(Vector2(a.right, a.top), Vector2(a.right, a.bottom)),
      for (final side in [-1, 1])
        _Guide([
          Vector2(side * a.right, guideTop),
          Vector2(side * drain, a.bottom),
          Vector2(side * a.right, a.bottom),
        ]),
      ..._flippers = [
        for (final side in [-1, 1])
          _Flipper(Vector2(side * pivot.x, pivot.y), flipper, side),
      ],
      CircleShuffler(
        Vector2(0, a.top + 0.35 * a.height),
        scale: 0.15 * small / CircleShuffler.reach,
        wireframe: true,
      ),
      ..._buckets = [
        for (final side in [-1, 1])
          _Bucket(
            Rect.fromCenter(
              center: Offset(
                side * (a.right - 0.06 * a.width - bucketWidth / 2),
                a.top + 0.15 * a.height + bucketHeight / 2,
              ),
              width: bucketWidth,
              height: bucketHeight,
            ),
          ),
      ],
    ]);
    _table?.next = table;
    world.add(_table = table);
  }

  var _started = false;

  void _start() {
    if (!_started && isLoaded) {
      _started = true;
      _ready.removeFromParent();
      spawn();
    }
  }

  void spawn() {
    if (!isLoaded || svgBodies.length + balls.length + _dropped > _maxBodies) {
      return;
    }
    final spawn = Vector2(0, _arena.top + 0.1 * _arena.height);
    final ballsFirst = random.nextBool();
    final bodies = [
      for (var i = 0; i < _dropped; i++)
        if (i.isEven == ballsFirst) randomBall() else randomSvg(spin: 2),
    ];
    final positions = spreadAround(
      spawn,
      [for (final body in bodies) body.radius],
      bounds: _arena.deflate(Wall.width),
      world: world.physicsWorld,
      random: random,
    );
    _current = {};
    for (final (i, body) in bodies.indexed) {
      final position = positions[i];
      final component = body.create(
        position,
        awayFrom(spawn, position, 2, random),
      );
      addBody(component);
      _current[component] = 0;
    }
  }

  /// Whether [body] is gone through the drain, is in a bucket, or has been at
  /// rest for [_restTime], after [dt] more seconds.
  bool _done(BodyComponent body, double dt) {
    if (body.isRemoving || body.isRemoved) {
      return true;
    }
    if (!body.isLoaded) {
      return false;
    }
    final position = body.body.position.toOffset();
    if (_buckets.any((bucket) => bucket.holds(position))) {
      return true;
    }
    final resting =
        body.body.linearVelocity.length < _restSpeed &&
        body.body.angularVelocity.abs() < _restSpeed;
    final time = _current[body] = resting ? _current[body]! + dt : 0;
    return time >= _restTime;
  }

  @override
  void update(double dt) {
    super.update(dt);
    final bottom = _arena.bottom + SvgBodies.maxSide;
    bool drained(BodyComponent body) =>
        body.isLoaded && body.body.position.y > bottom;
    final gone = [...svgBodies.where(drained), ...balls.where(drained)];
    if (gone.isNotEmpty) {
      removeBodies(gone);
    }
    for (final bucket in _buckets) {
      var count = 0;
      var top = double.infinity;
      for (final b in [...svgBodies, ...balls]) {
        if (!b.isLoaded || !bucket.holds(b.body.position.toOffset())) {
          continue;
        }
        count++;
        if (b.body.linearVelocity.length < _restSpeed) {
          top = math.min(top, b.body.position.y - _halfSize(b));
        }
      }
      bucket
        ..count = count
        ..full = top < bucket.inner.top + _fullRoom;
    }
    final done = [for (final body in _current.keys.toList()) _done(body, dt)];
    if (_started && !done.contains(false)) {
      spawn();
    }
  }

  @override
  KeyEventResult onKeyEvent(
    KeyEvent event,
    Set<LogicalKeyboardKey> keysPressed,
  ) {
    if (!_started) {
      if (event is KeyDownEvent) {
        _start();
      }
      return KeyEventResult.handled;
    }
    final key = event.logicalKey;
    final flipper = _flipperKeys[key];
    if (flipper == null) {
      return KeyEventResult.ignored;
    }
    if (event is KeyDownEvent) {
      _hold(flipper, key);
    } else if (event is KeyUpEvent) {
      _release(key);
    }
    return KeyEventResult.handled;
  }

  /// About half of [body]'s height.
  static double _halfSize(BodyComponent body) => switch (body) {
    Ball() => body.radius,
    SvgBody() => math.max(body.size.x, body.size.y) / 2,
    _ => 0,
  };

  void _hold(int flipper, Object holder) =>
      _flippers.elementAtOrNull(flipper)?.hold(holder);

  void _release(Object holder) {
    for (final flipper in _flippers) {
      flipper.release(holder);
    }
  }
}

class RevolutePinballWorld()
    extends Forge2DExampleWorld
    with TapCallbacks, HasGameRef<RevolutePinballExample>, BodiesHud {
  @override
  void onTapDown(TapDownEvent event) {
    super.onTapDown(event);
    if (!gameRef._started) {
      gameRef._start();
      return;
    }
    final position = event.canvasPosition;
    if (position.y > gameRef.size.y * 2 / 3) {
      gameRef._hold(position.x < gameRef.size.x / 2 ? 0 : 1, event.pointerId);
    }
  }

  @override
  void onTapUp(TapUpEvent event) {
    super.onTapUp(event);
    gameRef._release(event.pointerId);
  }

  @override
  void onTapCancel(TapCancelEvent event) {
    super.onTapCancel(event);
    gameRef._release(event.pointerId);
  }
}

/// The table's parts for one arena size. It stops drawing once [next] has
/// mounted all of its parts, and then goes, so that resizing doesn't flicker.
class _Table(final List<Component> _parts)
    extends Component
    with HasGameRef<RevolutePinballExample> {
  this : super(children: _parts);

  _Table? next;

  bool get _ready => isMounted && children.length == _parts.length;

  /// Counts its bodies in the world's body count.
  @override
  void onChildrenChanged(Component child, ChildrenChangeType type) {
    super.onChildrenChanged(child, type);
    if (child is BodyComponent) {
      (gameRef.world as BodiesHud).countBodies(
        type == ChildrenChangeType.added ? 1 : -1,
      );
    }
  }

  @override
  void update(double dt) {
    if (next?._ready ?? false) {
      removeFromParent();
    }
  }

  @override
  void renderTree(Canvas canvas) {
    if (!(next?._ready ?? false)) {
      super.renderTree(canvas);
    }
  }
}

class _Guide(final List<Vector2> _vertices)
    extends BodyComponent
    with GlowingBody {
  this : super(paint: Paint()..color = ExampleColors.slate);

  @override
  Body createBody() => world.createBody(BodyDef())
    ..createShape(
      Polygon(_vertices),
      ShapeDef(material: SurfaceMaterial(friction: 0.5)),
    );
}

/// An open-top bucket around [inner], a U path that collides as its convex
/// pieces, which glows once it's [full]. As a body comes in, its count fades
/// in above it for a while.
class _Bucket(final Rect inner) extends BodyComponent {
  static const _countCap = 2.4;

  static const _thickness = 0.6;

  /// How many segments make each of the bottom's half ellipses.
  static const _segments = 48;

  /// The radii and the center of the bottom's inner half ellipse, as wide as
  /// [inner], and at most as deep.
  late final _rx = inner.width / 2;
  late final _ry = math.min(_rx, inner.height);
  late final _center = Offset(inner.center.dx, inner.bottom - _ry);

  /// Whether [point] is inside the bucket.
  bool holds(Offset point) {
    final d = point - _center;
    return inner.contains(point) &&
        (d.dy <= 0 || math.pow(d.dx / _rx, 2) + math.pow(d.dy / _ry, 2) <= 1);
  }

  /// Straight sides down to the bottom's half ellipse.
  late final _outline = () {
    const w = _thickness;
    List<Vector2> arc(double rx, double ry, {required bool leftToRight}) =>
        List.generate(_segments + 1, (i) {
          final a = (leftToRight ? _segments - i : i) * math.pi / _segments;
          return Vector2(
            _center.dx + rx * math.cos(a),
            _center.dy + ry * math.sin(a),
          );
        });
    return [
      Vector2(inner.left - w, inner.top),
      Vector2(inner.left, inner.top),
      ...arc(_rx, _ry, leftToRight: true),
      Vector2(inner.right, inner.top),
      Vector2(inner.right + w, inner.top),
      ...arc(_rx + w, _ry + w, leftToRight: false),
    ];
  }();

  late final _path = Path()
    ..addPolygon([for (final v in _outline) v.toOffset()], true);

  var _paints = GlowPaints(ExampleColors.slate, 0.12);

  int count = 0;

  /// The count last frame, null before the first.
  int? _lastCount;

  VectorTextComponent? _countText;

  /// Whether its resting bodies leave less than
  /// [RevolutePinballExample._fullRoom] above them.
  bool full = false;

  @override
  void update(double dt) {
    final color = full ? ExampleColors.dynamicColor(4) : ExampleColors.slate;
    if (_paints.color != color) {
      _paints = GlowPaints(color, _paints.outlineWidth);
    }
    final last = _lastCount;
    if (last != null && count > last) {
      _showCount();
    }
    _lastCount = count;
  }

  void _showCount() {
    _countText?.removeFromParent();
    add(
      _countText =
          VectorTextComponent(
              text: '$count',
              capHeight: _countCap,
            )
            ..position = Vector2(
              inner.center.dx,
              inner.top - 0.5 - _countCap / 2,
            )
            ..opacity = 0
            ..add(
              SequenceEffect([
                OpacityEffect.fadeIn(EffectController(duration: 0.3)),
                OpacityEffect.fadeOut(
                  EffectController(duration: 0.5, startDelay: 2),
                ),
                RemoveEffect(),
              ]),
            ),
    );
  }

  @override
  void render(Canvas canvas) {
    canvas
      ..drawPath(_path, _paints.fill)
      ..drawPath(_path, _paints.outline);
  }

  @override
  Body createBody() {
    final body = world.createBody(BodyDef());
    for (final piece in convexPieces(
      _outline,
      minDistance: 4 * linearSlop,
      minWidth: 2 * linearSlop,
    )) {
      body.createShape(
        Polygon(piece),
        ShapeDef(material: SurfaceMaterial(friction: 0.5)),
      );
    }
    return body;
  }
}

/// A flipper [_length] meters long, on the left of its [_pivot] if [_side] is
/// 1, or on the right if -1. It lies on a guide at rest. Holding it kicks it
/// up, and a motor holds it at the top. Released, it falls back.
class _Flipper(final Vector2 _pivot, final double _length, final int _side)
    extends BodyComponent
    with GlowingBody {
  this : super(paint: Paint()..color = ExampleColors.dynamicColor(0));

  /// The kick's angular speed, and the motor's, in radians a second.
  static const _kickSpeed = 12.0;

  /// Its angle above the horizontal when fully kicked.
  static const _upAngle = 40 * math.pi / 180;

  /// How much faster than the other bodies it falls.
  static const _gravityScale = 16.0;

  /// Less than the other bodies', so that they slow it as it hits them.
  static const _density = 0.3;

  final _holders = <Object>{};
  late final RevoluteJoint _joint;

  void hold(Object holder) {
    if (_holders.isEmpty && isLoaded) {
      body.angularVelocity += _side * _kickSpeed;
      _joint.motorEnabled = true;
    }
    _holders.add(holder);
  }

  void release(Object holder) {
    if (_holders.remove(holder) && _holders.isEmpty && isLoaded) {
      _joint.motorEnabled = false;
      body.isAwake = true;
    }
  }

  @override
  Body createBody() {
    const angle = RevolutePinballExample._restAngle;
    final d = -_side * _length;
    final body =
        world.createBody(
          BodyDef(
            type: BodyType.dynamic,
            position: _pivot,
            rotation: Rot.fromAngle(-_side * angle),
            gravityScale: _gravityScale,
            isBullet: true,
          ),
        )..createShape(
          Polygon([
            Vector2.zero(),
            Vector2(d, 0),
            Vector2(d, -0.6),
            Vector2(0, -1.2),
          ]),
          ShapeDef(
            material: SurfaceMaterial(friction: 0.5),
            density: _density,
          ),
        );
    _joint = world.physicsWorld.createRevoluteJoint(
      RevoluteJointDef(
        bodyA: world.createBody(BodyDef()),
        bodyB: body,
        localAnchorA: _pivot.clone(),
        enableLimit: true,
        lowerAngle: math.min(-_side * angle, _side * _upAngle),
        upperAngle: math.max(-_side * angle, _side * _upAngle),
        motorSpeed: _side * _kickSpeed,
        maxMotorTorque: 2 * body.mass * 10 * _gravityScale * _length,
      ),
    );
    return body;
  }
}

class RasterizerRevolutePinballExample({
  required super.pieces,
  required super.status,
  @override required final SvgRenderer renderer,
}) extends RevolutePinballExample
    with HasRasterizer, ExampleRasterizer, RasterizerSvgs {
  this {
    RasterizerGpu.forceCanvas = forceCanvas;
  }

  @override
  PathComponent pathComponent(
    Path path,
    Paint paint, {
    Vector2? position,
    Anchor? anchor,
    double? maxSize,
    int? priority,
    RasterizerGlow? glow,
  }) => RasterizerPathComponent(
    path: path,
    paint: paint,
    position: position,
    anchor: anchor,
    maxSize: maxSize,
    priority: priority,
    glow: glow,
  );
}

class FlameSvgRevolutePinballExample({
  required super.pieces,
  required super.status,
  final SvgCache cache = defaultSvgCache,
}) extends RevolutePinballExample with FlameSvgs {
  @override
  SvgCacheMode get cacheMode => cache.mode;

  @override
  SvgCacheSize get cacheSize => cache.size;

  @override
  PathComponent pathComponent(
    Path path,
    Paint paint, {
    Vector2? position,
    Anchor? anchor,
    double? maxSize,
    int? priority,
    RasterizerGlow? glow,
  }) => PathComponent(
    path: path,
    paint: paint,
    position: position,
    anchor: anchor,
    priority: priority,
  );
}
