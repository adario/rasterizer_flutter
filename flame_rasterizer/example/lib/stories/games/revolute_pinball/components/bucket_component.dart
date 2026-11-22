import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flame/extensions.dart';
import 'package:flame_forge2d/flame_forge2d.dart' hide World;
import 'package:flame_rasterizer_example/commons/example_colors.dart';
import 'package:flame_rasterizer_example/commons/forge2d.dart';
import 'package:flame_rasterizer_example/commons/vector_text_component.dart';
import 'package:flame_rasterizer_example/stories/games/revolute_pinball/components/outlined.dart';
import 'package:flame_rasterizer_example/stories/games/revolute_pinball/revolute_pinball_example.dart';

/// An open-top bucket around [inner], a U path that collides as its convex
/// pieces, which glows once it's [full]. Once a body has stayed in it for
/// [_countTime], its count fades in above it for a while; once all its bodies
/// are at rest, so does how close they are to filling it, as a percentage,
/// below it.
class BucketComponent(final Rect inner)
    extends BodyComponent
    with GlowingBody, Outlined {
  this : super(paint: Paint()..color = ExampleColors.slate);

  /// It's full with at least [_fullCount] bodies, all at rest, whose area is
  /// at least [_fullShare] of its own.
  static const _fullCount = 2;
  static const _fullShare = 0.4;

  /// How long a body stays in it to count, in seconds.
  static const _countTime = 1.0;

  /// The score for each square meter of a body coming to rest in it, times
  /// its share.
  static const _scorePerArea = 400;

  /// How many times its bodies' area it gives back to the energy once full.
  static const _refund = 2.0;

  static const _countCap = 2.4;

  /// Its walls' thickness, outside [inner].
  static const thickness = 0.6;

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
    const w = thickness;
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

  /// Its bodies, with how long each has been in it, and still.
  var _inside = <BodyComponent, double>{};
  var _still = <BodyComponent, double>{};

  /// How many bodies counted at the last [track], null before the first.
  int? _count;

  /// The bodies that count and haven't scored yet.
  final _arrivals = <BodyComponent>{};

  /// Whether it's full, and so emptying.
  bool get full => _emptying.isNotEmpty;

  /// Whether [body] is one of the bodies that it empties.
  bool empties(BodyComponent body) => _emptying.containsKey(body);

  RevolutePinballExample get _game => findGame()! as RevolutePinballExample;

  /// How long emptying takes, and each body's share of it, in seconds.
  static const _emptyTime = 5.0;
  static const _shrinkTime = 2.0;

  /// The bodies emptying, which shrink from the bottom up, and the time since
  /// it started.
  final _emptying = <BodyComponent, _Shrink>{};
  double _emptyClock = 0;

  bool _atRest(BodyComponent b) =>
      _still[b]! >= RevolutePinballExample.restTime;

  /// Whether [body] has stayed in it for [_countTime].
  bool counts(BodyComponent body) => (_inside[body] ?? 0) >= _countTime;

  /// The area of its bodies when its share last showed, as a share of what
  /// fills it, up to 1, or 0 once it has emptied. The bodies from a game
  /// with another renderer set it without showing it.
  double get level => _level ?? 0;
  double? _level;

  /// Sets [level] back to 0, for a new game.
  void restart() => _level = 0;

  /// Whether [level] still counts the bodies that it empties.
  var _stale = false;

  /// The texts above and below it.
  final _texts = <bool, VectorTextComponent>{};

  /// Its inner area: a rectangle above a half ellipse.
  late final _area =
      inner.width * (inner.height - _ry) + math.pi * _rx * _ry / 2;

  /// The area of [bodies], as a share of its own.
  double _shareOf(Iterable<BodyComponent> bodies) =>
      bodies.fold(0.0, (sum, b) => sum + RevolutePinballExample.area(b)) /
      _area;

  double get _share => _shareOf(_inside.keys);

  /// How close [share] is to filling it, up to 1.
  static double _levelOf(double share) => math.min(1, share / _fullShare);

  static double _bottom(BodyComponent b) =>
      b.body.shapes.map((s) => s.aabb.upperBound.y).reduce(math.max);

  /// Updates its bodies from [bodies], after [dt] more seconds: once they're
  /// all at rest, scores those that came in, and starts emptying once full.
  void track(Iterable<BodyComponent> bodies, double dt) {
    _empty(dt);
    final inside = <BodyComponent, double>{};
    final still = <BodyComponent, double>{};
    for (final b in bodies) {
      if (!b.isLoaded ||
          _emptying.containsKey(b) ||
          !holds(b.body.position.toOffset())) {
        continue;
      }
      if (_game.settled.remove(b)) {
        inside[b] = _countTime;
        still[b] = RevolutePinballExample.restTime;
        continue;
      }
      final time = inside[b] = (_inside[b] ?? 0) + dt;
      still[b] = RevolutePinballExample.isStill(b.body)
          ? (_still[b] ?? 0) + dt
          : 0;
      if (time >= _countTime && time - dt < _countTime) {
        _arrivals.add(b);
      }
    }
    _inside = inside;
    _still = still;
    _arrivals.removeWhere((b) => !inside.containsKey(b));
    final count = inside.keys.where(counts).length;
    if (_count case final last? when count > last) {
      _show('$count', below: false);
    }
    _count = count;
    if (inside.isEmpty || !inside.keys.every((b) => counts(b) && _atRest(b))) {
      return;
    }
    final share = _share;
    if (_arrivals.isNotEmpty || _level == null) {
      _level = _levelOf(share);
      _stale = false;
    }
    if (_arrivals.isNotEmpty) {
      for (final b in _arrivals) {
        _game.score += (_scorePerArea * RevolutePinballExample.area(b) * share)
            .round();
      }
      _arrivals.clear();
      _game.play(PinballSound.score);
      _show('${(100 * _levelOf(share)).round()}%', below: true);
    }
    if (!full && inside.length >= _fullCount && share >= _fullShare) {
      _startEmptying(inside.keys.toList());
    }
  }

  /// Frees [_refund] times the drained area that [bodies] take, and shrinks
  /// them from the bottom up.
  void _startEmptying(List<BodyComponent> bodies) {
    final game = _game..play(PinballSound.empty);
    game.drainedArea = math.max(
      0,
      game.drainedArea -
          _refund *
              bodies.fold(
                0.0,
                (sum, b) => sum + RevolutePinballExample.area(b),
              ),
    );
    bodies.sort((a, b) => _bottom(b).compareTo(_bottom(a)));
    final step = bodies.length < 2
        ? 0.0
        : (_emptyTime - _shrinkTime) / (bodies.length - 1);
    for (final (i, b) in bodies.indexed) {
      _emptying[b] = _Shrink(b, i * step);
    }
    _emptyClock = 0;
    _stale = true;
    _inside = {};
    _still = {};
    _count = 0;
    _arrivals.clear();
  }

  /// Shrinks the emptying bodies [dt] seconds further, and removes them once
  /// done.
  void _empty(double dt) {
    _emptying.removeWhere((b, _) => b.isRemoving || b.isRemoved);
    if (_emptying.isEmpty) {
      return;
    }
    _emptyClock += dt;
    for (final shrink in _emptying.values) {
      shrink.update((_emptyClock - shrink.start) / _shrinkTime);
    }
    if (_emptyClock >= _emptyTime) {
      _game.removeBodies(_emptying.keys.toList());
      _emptying.clear();
      if (_stale) {
        _level = 0;
      }
    }
  }

  @override
  void update(double dt) {
    paint.color = full ? ExampleColors.dynamicColor(4) : ExampleColors.slate;
    super.update(dt);
  }

  /// Fades in [text] for a while, [below] it or above.
  void _show(String text, {required bool below}) {
    _texts[below]?.removeFromParent();
    add(
      _texts[below] =
          VectorTextComponent(
              text: text,
              capHeight: _countCap,
            )
            ..position = Vector2(
              inner.center.dx,
              below
                  ? inner.bottom + thickness + 0.5 + _countCap / 2
                  : inner.top - 0.5 - _countCap / 2,
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

/// Shrinks [_body], its shapes and its drawing, as it empties from a bucket,
/// [start] seconds after the emptying starts.
class _Shrink(final BodyComponent _body, final double start) {
  static const _smallest = 0.2;

  /// Its shapes and drawing at full size, saved before the first shrink.
  late final _shapes = [
    for (final shape in _body.body.shapes)
      (
        geometry: shape.geometry,
        def: ShapeDef(
          density: shape.density,
          material: SurfaceMaterial(
            friction: shape.friction,
            restitution: shape.restitution,
          ),
          filter: shape.filter,
          enableContactEvents: shape.contactEventsEnabled,
        ),
      ),
  ];
  late final _children = [
    for (final c in _body.children.whereType<PositionComponent>())
      (component: c, position: c.position.clone(), scale: c.scale.clone()),
  ];

  var _scale = 1.0;

  /// Scales it for [progress] from 0 to 1, by recreating its shapes.
  void update(double progress) {
    final scale = 1 + (_smallest - 1) * progress.clamp(0, 1);
    if (scale == _scale) {
      return;
    }
    final shapes = _shapes;
    _scale = scale;
    final body = _body.body;
    for (final shape in body.shapes) {
      shape.destroy();
    }
    for (final (:geometry, :def) in shapes) {
      final scaled = switch (geometry) {
        Circle(:final center, :final radius) => Circle(
          center: center * scale,
          radius: radius * scale,
        ),
        Polygon(:final points?, :final radius) => Polygon([
          for (final p in points) p * scale,
        ], radius: radius * scale),
        _ => geometry,
      };
      try {
        body.createShape(scaled, def);
      } on ArgumentError {
        // Too small for a hull: it goes.
      }
    }
    for (final (:component, :position, :scale) in _children) {
      component
        ..position = position * _scale
        ..scale = scale * _scale;
    }
  }
}
