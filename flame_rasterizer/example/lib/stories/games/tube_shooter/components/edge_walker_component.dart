import 'dart:math' as math;
import 'dart:ui';

import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/enemy_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube.dart';

/// An edge-walker, which spins along the edges between lanes, where the
/// tube's spokes are.
///
/// It comes at its lane's middle, and goes to one of the lane's edges. On an
/// edge, it climbs the tube, and now and then crosses a neighbouring lane to
/// that lane's other edge. Only while it crosses can a shot down the lane's
/// middle destroy it. At the rim, it crosses toward the ship, and destroys it
/// while crossing the ship's lane or standing on one of its edges.
///
/// Its [lane] is the one it crosses, or the one that starts at its [edge].
class EdgeWalkerComponent({required super.lane, required super.depth})
    extends EnemyComponent {
  this : super(EnemyKind.edgeWalker);

  /// How fast it spins, in turns a second.
  static const spin = 1.5;

  /// The edge it's on, or crosses from, as the index of the tube's point
  /// there.
  int get edge => _edge;
  int _edge = 0;

  /// The edge it crosses to, if any, and how far across it is, from 0 to 1.
  int? _crossTo;
  double _crossProgress = 0;

  /// Seconds until it crosses, at the first round's pace.
  double _untilCross = 0;

  /// How far round its spin is, from 0 to 1.
  double _turns = 0;

  bool get isCrossing => _crossTo != null;

  @override
  bool get canBeShot => isCrossing;

  @override
  Future<void> onLoad() async {
    // It starts halfway across its lane, toward one of the lane's edges.
    final next = gameRef.view.tube.pointAfter(lane);
    if (gameRef.random.nextBool()) {
      _edge = next;
      cross(lane);
    } else {
      _edge = lane;
      cross(next);
    }
    _crossProgress = 0.5;
    _untilCross = between(gameRef.level.crossPeriod);
    await super.onLoad();
  }

  @override
  bool destroysShip(int shipLane) =>
      depth == 0 &&
      (isCrossing
          ? lane == shipLane
          : _edge == shipLane ||
                _edge == gameRef.view.tube.pointAfter(shipLane));

  /// Crosses to edge [to], next to its own, unless it's already crossing.
  void cross(int to) {
    if (_crossTo != null) {
      return;
    }
    _crossTo = to;
    _crossProgress = 0;
    lane = to == gameRef.view.tube.pointAfter(_edge) ? _edge : to;
  }

  /// Crosses to the next edge on [side], 1 or -1, or to the one on the other
  /// side if an open tube ends there.
  void _crossAside(int side) {
    final tube = gameRef.view.tube;
    cross((tube.pointBeside(_edge, side) ?? tube.pointBeside(_edge, -side))!);
  }

  @override
  void move(double dt) {
    super.move(dt);
    final level = gameRef.level;
    final pace = gameRef.pace;
    _turns = (_turns + dt * pace * spin) % 1;
    final to = _crossTo;
    if (to != null) {
      _crossProgress += dt * pace / level.crossTime;
      if (_crossProgress >= 1) {
        _edge = to;
        lane = math.min(to, gameRef.view.tube.laneCount - 1);
        _crossTo = null;
      }
      return;
    }
    _untilCross -= dt * pace;
    if (depth > 0) {
      depth = math.max(
        0,
        depth - dt * pace * Tube.depth / level.edgeWalkerTime,
      );
      if (depth == 0) {
        _untilCross = math.min(_untilCross, level.rimCrossPeriod);
      } else if (_untilCross <= 0) {
        _untilCross = between(level.crossPeriod);
        _crossAside(gameRef.random.nextBool() ? 1 : -1);
      }
    } else if (_untilCross <= 0) {
      _untilCross = level.rimCrossPeriod;
      final toward = gameRef.towardShip(_edge);
      if (toward != 0) {
        _crossAside(toward);
      }
    }
  }

  @override
  void place() {
    final to = _crossTo;
    final view = gameRef.view;
    final tube = view.tube;
    final point = to == null
        ? tube.points[_edge]
        : Offset.lerp(tube.points[_edge], tube.points[to], _crossProgress)!;
    final scale = view.scaleAt(depth);
    final at = point * scale;
    position.setValues(at.dx, at.dy);
    angle = _turns * 2 * math.pi;
    this.scale.splat(tube.laneWidth * scale);
  }
}
