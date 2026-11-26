import 'dart:math' as math;

import 'package:flame_rasterizer_example/stories/games/tube_runner/components/runner_enemy_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_runner/endless_tube.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/edge_walker_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/enemy_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/level.dart';

/// An edge-walker, which climbs the tube on the edges between lanes, and
/// crosses a neighbouring lane now and then, as Tube Shooter's does at its
/// first level's pace. Only while it crosses can a shot destroy it. It
/// destroys the ship while crossing the ship's lane, or on one of its edges.
class RunnerEdgeWalkerComponent(int lane, @override var double at, {super.from})
    extends RunnerEnemyComponent {
  this : super(EnemyKind.edgeWalker, lane);

  static final level = levels.first;

  @override
  late int lane = from?.lane ?? spawnLane;

  @override
  int get currentLane => lane;

  int _edge = 0;
  int? _crossTo;
  double _crossProgress = 0;
  double _untilCross = 0;
  double _turns = 0;
  bool _started = false;

  bool get isCrossing => _crossTo != null;

  @override
  bool get canBeShot => isCrossing;

  @override
  bool hits(int shipLane) {
    _start();
    return isCrossing
        ? lane == shipLane
        : _edge == shipLane || _edge == gameRef.view.tube.pointAfter(shipLane);
  }

  @override
  Record get ownSnapshot => (
    edge: _edge,
    crossTo: _crossTo,
    crossProgress: _crossProgress,
    untilCross: _untilCross,
    turns: _turns,
  );

  /// Starts it halfway across its lane, toward one of its edges, as in Tube
  /// Shooter, or where its snapshot says.
  void _start() {
    if (_started) {
      return;
    }
    _started = true;
    if (from?.own case (
      :final int edge,
      :final int? crossTo,
      :final double crossProgress,
      :final double untilCross,
      :final double turns,
    )) {
      _edge = edge;
      _crossTo = crossTo;
      _crossProgress = crossProgress;
      _untilCross = untilCross;
      _turns = turns;
      return;
    }
    final next = gameRef.view.tube.pointAfter(lane);
    if (gameRef.random.nextBool()) {
      _edge = next;
      _cross(lane);
    } else {
      _edge = lane;
      _cross(next);
    }
    _crossProgress = 0.5;
    _untilCross = _between(level.crossPeriod);
  }

  void _cross(int to) {
    _crossTo = to;
    _crossProgress = 0;
    lane = to == gameRef.view.tube.pointAfter(_edge) ? _edge : to;
  }

  @override
  TubeMark get mark {
    _start();
    final p = _crossTo == null ? 0.0 : _crossProgress;
    return (
      lane: lane,
      at: at,
      flip: null,
      across: lane == _edge ? p : 1 - p,
    );
  }

  @override
  void move(double dt) {
    _start();
    at -= RunnerEnemyComponent.climbSpeed * dt;
    _turns = (_turns + dt * EdgeWalkerComponent.spin) % 1;
    final to = _crossTo;
    if (to != null) {
      _crossProgress += dt / level.crossTime;
      if (_crossProgress >= 1) {
        _edge = to;
        lane = math.min(to, gameRef.view.tube.laneCount - 1);
        _crossTo = null;
      }
      return;
    }
    _untilCross -= dt;
    if (_untilCross <= 0) {
      _untilCross = _between(level.crossPeriod);
      final tube = gameRef.view.tube;
      final side = gameRef.random.nextBool() ? 1 : -1;
      _cross(
        (tube.pointBeside(_edge, side) ?? tube.pointBeside(_edge, -side))!,
      );
    }
  }

  @override
  void placeAt(ShapePlace? place) {
    super.placeAt(place);
    angle += _turns * 2 * math.pi;
  }

  double _between(Range range) =>
      range.least + (range.most - range.least) * gameRef.random.nextDouble();
}
