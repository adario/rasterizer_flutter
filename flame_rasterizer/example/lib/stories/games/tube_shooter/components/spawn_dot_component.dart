import 'dart:math' as math;
import 'dart:ui';

import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/dot_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/enemy_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube.dart';
import 'package:flutter/material.dart' show Colors;

/// An enemy of [kind] still to come: a dot in its colour on the tube's far
/// end.
///
/// It wanders round the far end, turning back at random, faster each round.
/// Once it [arrive]s, it moves to its lane's middle, flashing white, until it
/// [hasArrived]. The game then replaces it with the enemy, in that lane.
class SpawnDotComponent(final EnemyKind kind, {required double at})
    extends DotComponent {
  this : super(kind.color);

  /// Its width, in device pixels.
  static const pixels = 3.0;

  /// Its wandering speed in the first round, in lanes a second: the least and
  /// the most.
  static const speeds = (0.5, 1.5);

  /// The seconds before it turns back in the first round: the least and the
  /// most.
  static const turnPeriod = (1.0, 3.0);

  /// The seconds it takes to arrive.
  static const arriveTime = 0.3;

  /// The seconds each flash lasts as it arrives.
  static const flashTime = 0.05;

  /// Its speed toward its lane's middle as it arrives, in lanes a second.
  static const arriveSpeed = 4.0;

  /// Where it is round the far end, in lanes from the tube's first point.
  double at = at;

  double _speed = 0;
  double _turnIn = 0;

  /// The seconds since it began to arrive, if it has.
  double? _arriving;

  bool _white = false;

  /// The lane it's in.
  int get lane => math.min(at.floor(), gameRef.view.tube.laneCount - 1);

  bool get isArriving => _arriving != null;

  bool get hasArrived => (_arriving ?? 0) >= arriveTime;

  /// Starts arriving.
  void arrive() => _arriving = 0;

  /// Stops arriving, if it was, and wanders again.
  void wander() {
    _arriving = null;
    _flash(false);
  }

  @override
  Future<void> onLoad() async {
    final random = gameRef.random;
    final (least, most) = speeds;
    _speed =
        (least + (most - least) * random.nextDouble()) *
        (random.nextBool() ? 1 : -1);
    _turnIn = _turnPeriod();
    await super.onLoad();
  }

  double _turnPeriod() {
    final (least, most) = turnPeriod;
    return least + (most - least) * gameRef.random.nextDouble();
  }

  @override
  void move(double dt) {
    final arriving = _arriving;
    if (arriving == null) {
      final pace = gameRef.pace;
      final tube = gameRef.view.tube;
      _turnIn -= dt * pace;
      if (_turnIn <= 0) {
        _speed = -_speed;
        _turnIn = _turnPeriod();
      }
      at += _speed * pace * dt;
      if (!tube.isOpen) {
        at %= tube.laneCount;
      } else if (at < 0 || at > tube.laneCount) {
        _speed = -_speed;
        at = at.clamp(0, tube.laneCount).toDouble();
      }
      return;
    }
    _arriving = arriving + dt;
    final step = arriveSpeed * dt;
    at += (lane + 0.5 - at).clamp(-step, step);
    _flash((arriving / flashTime).floor().isEven);
  }

  /// Tints it white, or clears the tint. A tint doesn't import its dot again.
  void _flash(bool white) {
    if (white == _white) {
      return;
    }
    _white = white;
    if (white) {
      drawing.tint(Colors.white);
    } else {
      drawing.paint.colorFilter = null;
    }
  }

  @override
  void place() {
    final tube = gameRef.view.tube;
    final lane = this.lane;
    final point = Offset.lerp(
      tube.points[lane],
      tube.points[tube.pointAfter(lane)],
      at - lane,
    )!;
    final drawn = gameRef.view.project(point, Tube.depth);
    position.setValues(drawn.dx, drawn.dy);
    sizeTo(pixels);
  }
}
