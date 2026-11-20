import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flame/events.dart';
import 'package:flame/extensions.dart';
import 'package:flame/geometry.dart' show convexPieces;
import 'package:flame_forge2d/flame_forge2d.dart' hide World;
import 'package:flame_rasterizer/flame_rasterizer.dart';
import 'package:flame_rasterizer_example/commons/example_colors.dart';
import 'package:flame_rasterizer_example/commons/forge2d.dart';
import 'package:flame_rasterizer_example/commons/outline_paints.dart';
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
    it, and drops 15 bodies over a wheel. Once each is in a bucket, gone
    through the drain, or at rest, the wheel turns the other way, amber until
    it's at full speed, and the next 15 drop. Left or A, Right or D, or a tap
    in the bottom third's left or right half flips a flipper. Fill both
    buckets.
  ''';

  static final _flipperKeys = {
    LogicalKeyboardKey.arrowLeft: 0,
    LogicalKeyboardKey.keyA: 0,
    LogicalKeyboardKey.arrowRight: 1,
    LogicalKeyboardKey.keyD: 1,
  };

  static const _dropped = 15;
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

  /// Smaller balls can get stuck at the flippers' tips.
  @override
  double get minBallRadius => 0.52;

  /// MultipleShapes' path colors: each SVG's own, and the balls' in turn.
  @override
  Color nextColor([String? svg]) {
    const colors = OutlinePaints.colors;
    final index = svg == null ? tint++ : randomSvgNames.indexOf(svg);
    return colors[index % colors.length];
  }

  /// The SVG's outline, drawn as MultipleShapes' paths.
  @override
  PositionComponent svgImage(SvgBody body) {
    final outline = body.svg.outline;
    final rect = outline.rect;
    final bounds = outline.path.getBounds();
    final scale = Vector2(body.size.x / rect.width, body.size.y / rect.height);
    return outlineComponent(
        outline.path,
        OutlinePaints.of(body.color, rect.longestSide),
        maxSize: 3 * metersToPixels * SvgBodies.maxSide,
      )
      ..position = Vector2(
        (bounds.left - rect.center.dx) * scale.x,
        (bounds.top - rect.center.dy) * scale.y,
      )
      ..scale = scale;
  }

  /// A unit circle, which every ball draws, scaled to its radius.
  static final _circle = Path()
    ..addOval(Rect.fromCircle(center: Offset.zero, radius: 1));

  /// Draws [ball] as MultipleShapes' paths.
  void _drawAsPath(Ball ball) {
    ball
      ..glows = false
      ..add(
        outlineComponent(
            _circle,
            OutlinePaints.of(ball.paint.color, 2),
            // The largest balls are 2 meters wide.
            maxSize: 3 * metersToPixels * 2,
          )
          ..position = Vector2.all(-ball.radius)
          ..scale = Vector2.all(ball.radius),
      );
  }

  /// Creates a component of the game's renderer that draws [path] with
  /// [paintLayers], imported for [maxSize], at a device pixel ratio of up to
  /// 3.
  PathComponent outlineComponent(
    Path path,
    List<Paint> paintLayers, {
    required double maxSize,
  });

  /// The last trail of each body a flipper kicked.
  final _trails = <BodyComponent, _Trail>{};

  _Table? _table;
  var _flippers = <_Flipper>[];
  CircleShuffler? _wheel;
  var _buckets = <_Bucket>[];
  final _ready = VectorTextComponent(
    text: 'READY',
    capHeight: VectorTextComponent.maxCapHeight,
  );

  /// Whether the next drop waits for the wheel to turn the other way.
  var _queued = false;

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
    // The left flipper and guide, mirrored for the right ones: the tip ends
    // at the drain, and the guide's recess under it at the bottom.
    const angle = _restAngle;
    const gap = _Flipper.gap;
    final bottom = _Flipper.bottomAngle(flipper);
    final tip = _Flipper.tipCenter(flipper);
    final floor =
        (tip +
              Vector2(math.cos(bottom), math.sin(bottom)) *
                  (_Flipper.tipRadius + gap))
          ..rotate(angle);
    final pivot = Vector2(
      -drain - _Flipper.tipRadius - (tip.clone()..rotate(angle)).x,
      a.bottom - floor.y,
    );
    final socket = [
      for (final p in _Flipper.arc(
        Vector2.zero(),
        _Flipper.radius + gap,
        math.pi + math.asin(_Flipper.radius / (_Flipper.radius + gap)),
        bottom,
      ))
        p
          ..rotate(angle)
          ..add(pivot),
    ];
    final top = socket.first;
    final guide = [
      Vector2(a.left, top.y - (top.x - a.left) * math.tan(angle)),
      ...socket,
      pivot + floor,
      Vector2(a.left, a.bottom),
    ];
    final bucketWidth = math.max(0.2 * a.width, 2 * SvgBodies.maxSide);
    final bucketHeight = 0.2 * small;
    final table = _Table([
      Wall(Vector2(a.left, a.top), Vector2(a.right, a.top)),
      Wall(Vector2(a.left, a.top), Vector2(a.left, a.bottom)),
      Wall(Vector2(a.right, a.top), Vector2(a.right, a.bottom)),
      _Guide(guide),
      _Guide([for (final v in guide.reversed) Vector2(-v.x, v.y)]),
      ..._flippers = [
        for (final side in [-1, 1])
          _Flipper(Vector2(-side * pivot.x, pivot.y), flipper, side),
      ],
      _wheel = CircleShuffler(
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
    if (!isLoaded) {
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
      if (component is Ball) {
        _drawAsPath(component);
      }
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

  /// Starts a trail behind [body]'s component, unless its last one is still
  /// going.
  void _kicked(Body body) {
    for (final component in [...svgBodies, ...balls]) {
      if (component.isLoaded && component.body == body) {
        if (_trails[component]?.over ?? true) {
          world.add(_trails[component] = _Trail(component));
        }
        return;
      }
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    _trails.removeWhere((_, trail) => trail.over);
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
    if (_started &&
        !done.contains(false) &&
        svgBodies.length + balls.length + _dropped <= _maxBodies) {
      if (!_queued) {
        _queued = true;
        _wheel?.reverse();
      } else if (!(_wheel?.reversing ?? false)) {
        _queued = false;
        spawn();
      }
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
  void update(double dt) {
    super.update(dt);
    final events = physicsWorld.contactEvents;
    for (final flipper in gameRef._flippers) {
      flipper.track(events);
      if (flipper.kicking) {
        flipper.touching.forEach(gameRef._kicked);
      }
    }
  }

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

/// A body drawn as its [outline], in its own coordinates, that collides as
/// the outline's convex pieces.
mixin _Outlined on GlowingBody {
  List<Vector2> get outline;

  @override
  Path get glowPath =>
      Path()..addPolygon([for (final v in outline) v.toOffset()], true);

  void addPieces(Body body, ShapeDef def) {
    for (final piece in convexPieces(
      outline,
      minDistance: 4 * linearSlop,
      minWidth: 2 * linearSlop,
    )) {
      body.createShape(Polygon(piece), def);
    }
  }
}

/// A slide down to a flipper, with a recess for it.
class _Guide(@override final List<Vector2> outline)
    extends BodyComponent
    with GlowingBody, _Outlined {
  this : super(paint: Paint()..color = ExampleColors.slate);

  @override
  Body createBody() {
    final body = world.createBody(BodyDef());
    addPieces(body, ShapeDef(material: SurfaceMaterial(friction: 0.5)));
    return body;
  }
}

/// An open-top bucket around [inner], a U path that collides as its convex
/// pieces, which glows once it's [full]. As a body comes in, its count fades
/// in above it for a while.
class _Bucket(final Rect inner)
    extends BodyComponent
    with GlowingBody, _Outlined {
  this : super(paint: Paint()..color = ExampleColors.slate);

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
  @override
  late final outline = () {
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

  int count = 0;

  /// The count last frame, null before the first.
  int? _lastCount;

  VectorTextComponent? _countText;

  /// Whether its resting bodies leave less than
  /// [RevolutePinballExample._fullRoom] above them.
  bool full = false;

  @override
  void update(double dt) {
    paint.color = full ? ExampleColors.dynamicColor(4) : ExampleColors.slate;
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
  Body createBody() {
    final body = world.createBody(BodyDef());
    addPieces(body, ShapeDef(material: SurfaceMaterial(friction: 0.5)));
    return body;
  }
}

/// A flipper [_length] meters from its pivot's center to its tip's, on the
/// left of its [_pivot] if [_side] is 1, or on the right if -1. It lies in a
/// guide's recess at rest, its flat top along the guide. Holding it kicks it
/// up, and a motor holds it at the top. Released, it falls back.
class _Flipper(final Vector2 _pivot, final double _length, final int _side)
    extends BodyComponent
    with GlowingBody, _Outlined {
  this : super(paint: Paint()..color = ExampleColors.dynamicColor(0));

  /// The radii of its round ends.
  static const radius = 0.6;
  static const tipRadius = 0.3;

  /// The room between it and its guide's recess.
  static const gap = 0.1;

  static const _segments = 16;

  /// For a left flipper with its pivot at the origin and its top along the
  /// x axis: its tip's center, and the angle of its bottom edge's normal.
  static Vector2 tipCenter(double length) =>
      Vector2(length, tipRadius - radius);
  static double bottomAngle(double length) =>
      2 * math.atan2(tipRadius - radius, length) + math.pi / 2;

  /// The arc around [center] from angle [from] to [to].
  static List<Vector2> arc(
    Vector2 center,
    double radius,
    double from,
    double to,
  ) => List.generate(_segments + 1, (i) {
    final a = from + (to - from) * i / _segments;
    return center + Vector2(math.cos(a), math.sin(a)) * radius;
  });

  @override
  late final outline = () {
    final bottom = bottomAngle(_length);
    final left = [
      ...arc(Vector2.zero(), radius, bottom, 3 * math.pi / 2),
      ...arc(tipCenter(_length), tipRadius, -math.pi / 2, bottom),
    ];
    return _side < 0
        ? left
        : [for (final v in left.reversed) Vector2(-v.x, v.y)];
  }();

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

  /// The bodies touching it.
  final touching = <Body>{};

  /// Whether it's swinging up.
  bool get kicking => isLoaded && _side * body.angularVelocity > 1;

  /// Updates [touching] with [events].
  void track(ContactEvents events) {
    if (!isLoaded) {
      return;
    }
    Body? other(Shape a, Shape b) => !a.isValid || !b.isValid
        ? null
        : (a.body == body ? b.body : (b.body == body ? a.body : null));
    for (final event in events.begin) {
      if (other(event.shapeA, event.shapeB) case final other?) {
        touching.add(other);
      }
    }
    for (final event in events.end) {
      if (other(event.shapeA, event.shapeB) case final other?) {
        touching.remove(other);
      }
    }
    touching.removeWhere((other) => !other.isValid);
  }

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
    final body = world.createBody(
      BodyDef(
        type: BodyType.dynamic,
        position: _pivot,
        rotation: Rot.fromAngle(-_side * angle),
        gravityScale: _gravityScale,
        isBullet: true,
      ),
    );
    addPieces(
      body,
      ShapeDef(
        material: SurfaceMaterial(friction: 0.5),
        density: _density,
        enableContactEvents: true,
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

/// A trail of [_body]'s center of mass for [_time] seconds, below all else:
/// one curve per step, which matches its positions and velocities at both
/// ends. Over the second half, it fades from its oldest curve to its newest.
class _Trail(final BodyComponent _body)
    extends Component
    with HasGameRef<RevolutePinballExample> {
  this : super(priority: -1);

  static const _time = 1.0;

  /// The width of the fade's edge, as a share of [_time].
  static const _edge = 0.3;

  static const _width = 0.2;

  late final _color = switch (_body) {
    SvgBody(:final color) => color,
    _ => _body.paint.color,
  };

  var _age = 0.0;
  Vector2? _position;
  Vector2? _velocity;
  final _curves = <({PathComponent curve, double age})>[];

  bool get over => _age >= _time;

  @override
  void update(double dt) {
    if (dt == 0) {
      return;
    }
    _age += dt;
    if (over) {
      removeFromParent();
      return;
    }
    if (_body.isLoaded && !_body.isRemoving && !_body.isRemoved) {
      _record(dt);
    }
    final front = (2 * _age / _time - 1) * (1 + _edge);
    _curves.removeWhere((c) {
      final opacity = ((c.age / _time + _edge - front) / _edge).clamp(0.0, 1.0);
      c.curve.opacity = opacity;
      if (opacity == 0) {
        c.curve.removeFromParent();
      }
      return opacity == 0;
    });
  }

  /// Adds the curve from the last step's position to this one's, [dt]
  /// seconds later.
  void _record(double dt) {
    final p1 = _body.body.worldCenterOfMass;
    final v1 = _body.body.linearVelocity;
    final p0 = _position;
    final v0 = _velocity;
    _position = p1;
    _velocity = v1;
    if (p0 == null || v0 == null) {
      return;
    }
    final c0 = p0 + v0 * (dt / 3);
    final c1 = p1 - v1 * (dt / 3);
    final path = Path()
      ..moveTo(p0.x, p0.y)
      ..cubicTo(c0.x, c0.y, c1.x, c1.y, p1.x, p1.y);
    final bounds = path.getBounds();
    final curve = gameRef.pathComponent(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _width
        ..strokeCap = StrokeCap.round
        ..color = _color,
      position: bounds.topLeft.toVector2(),
      // At a device pixel ratio of up to 3.
      maxSize: 3 * gameRef.metersToPixels * (bounds.longestSide + _width),
    );
    _curves.add((curve: curve, age: _age));
    add(curve);
  }
}

class RasterizerRevolutePinballExample({
  required super.pieces,
  required super.status,
  @override required final SvgRenderer renderer,
}) extends RevolutePinballExample
    with
        HasRasterizer,
        ExampleRasterizer,
        RasterizerSvgs,
        RasterizerPathComponents {
  this {
    RasterizerGpu.forceCanvas = forceCanvas;
  }

  @override
  PathComponent outlineComponent(
    Path path,
    List<Paint> paintLayers, {
    required double maxSize,
  }) => RasterizerPathComponent(
    path: path,
    paintLayers: paintLayers,
    maxSize: maxSize,
    // Its polygons aren't used.
    sampling: path.getBounds().longestSide,
  );
}

class FlameSvgRevolutePinballExample({
  required super.pieces,
  required super.status,
  final SvgCache cache = defaultSvgCache,
}) extends RevolutePinballExample with FlameSvgs, FlamePathComponents {
  @override
  SvgCacheMode get cacheMode => cache.mode;

  @override
  SvgCacheSize get cacheSize => cache.size;

  @override
  PathComponent outlineComponent(
    Path path,
    List<Paint> paintLayers, {
    required double maxSize,
  }) => PathComponent(
    path: path,
    paintLayers: paintLayers,
    // Its polygons aren't used.
    sampling: path.getBounds().longestSide,
  );
}
