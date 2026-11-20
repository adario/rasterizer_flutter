import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame_forge2d/flame_forge2d.dart' hide World;
import 'package:flame_rasterizer/flame_rasterizer.dart';
import 'package:flame_rasterizer_example/commons/example_colors.dart';
import 'package:flame_rasterizer_example/commons/forge2d.dart';
import 'package:flame_rasterizer_example/commons/svg_renderers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show KeyEventResult;

abstract class RevolutePinballExample({
  @override required var bool pieces,
  required super.status,
}) extends Forge2DExampleGame with ExampleSvgs, SvgBodies, KeyboardEvents {
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
    A pinball with the bodies of Revolute Joint Svgs. Space, or a double tap
    above the bottom third, drops 10 bodies over a wheel. Left or A, Right or
    D, or a tap in the bottom third's left or right half flips a flipper.
    Bodies that fall through the drain are gone.
  ''';

  static final _flipperKeys = {
    LogicalKeyboardKey.arrowLeft: 0,
    LogicalKeyboardKey.keyA: 0,
    LogicalKeyboardKey.arrowRight: 1,
    LogicalKeyboardKey.keyD: 1,
  };

  static const _dropped = 10;
  static const _maxBodies = 100;

  /// The flippers' angle at rest, and the guides' slope.
  static const _restAngle = math.pi / 6;

  @override
  final random = math.Random();

  _Table? _table;
  var _flippers = <_Flipper>[];

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

  /// Rebuilds the walls, the guides, the flippers and the wheel for the
  /// arena's size.
  void _buildTable() {
    final a = _arena;
    final drain = math.max(0.06 * a.width, SvgBodies.maxSide);
    final flipper = 0.18 * a.width;
    final pivot = Vector2(
      drain + flipper * math.cos(_restAngle),
      a.bottom - flipper * math.sin(_restAngle),
    );
    final guideTop = a.bottom - (a.right - drain) * math.tan(_restAngle);
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
        scale: 0.15 * a.height / CircleShuffler.reach,
        wireframe: true,
      ),
    ]);
    _table?.next = table;
    world.add(_table = table);
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
    for (final (i, body) in bodies.indexed) {
      final position = positions[i];
      addBody(body.create(position, awayFrom(spawn, position, 2, random)));
    }
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
  }

  @override
  KeyEventResult onKeyEvent(
    KeyEvent event,
    Set<LogicalKeyboardKey> keysPressed,
  ) {
    final key = event.logicalKey;
    if (event is KeyDownEvent && key == LogicalKeyboardKey.space) {
      spawn();
      return KeyEventResult.handled;
    }
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
  DateTime? _lastTap;

  @override
  void onTapDown(TapDownEvent event) {
    super.onTapDown(event);
    final position = event.canvasPosition;
    if (position.y > gameRef.size.y * 2 / 3) {
      _lastTap = null;
      gameRef._hold(position.x < gameRef.size.x / 2 ? 0 : 1, event.pointerId);
      return;
    }
    final now = DateTime.now();
    final last = _lastTap;
    if (last != null && now.difference(last).inMilliseconds < 300) {
      _lastTap = null;
      gameRef.spawn();
    } else {
      _lastTap = now;
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
class _Table(final List<Component> _parts) extends Component {
  this : super(children: _parts);

  _Table? next;

  bool get _ready => isMounted && children.length == _parts.length;

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
          ShapeDef(material: SurfaceMaterial(friction: 0.5)),
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
}
