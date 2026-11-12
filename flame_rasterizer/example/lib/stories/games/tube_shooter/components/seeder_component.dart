import 'dart:math' as math;

import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/enemy_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube.dart';

/// A seeder, which lays spikes.
///
/// It climbs its lane up to the level's `seederTurn`, growing the lane's
/// spike behind it. Then it goes back down, and climbs another lane.
class SeederComponent({required super.lane, required super.depth})
    extends EnemyComponent {
  this : super(EnemyKind.seeder);

  bool _descending = false;

  @override
  void move(double dt) {
    super.move(dt);
    final level = gameRef.level;
    final turn = level.seederTurn * Tube.depth;
    final step = dt * gameRef.pace * (Tube.depth - turn) / level.seederTime;
    if (!_descending) {
      depth = math.max(turn, depth - step);
      gameRef.spikes.grow(lane, Tube.depth - depth);
      _descending = depth == turn;
    } else {
      depth = math.min(Tube.depth, depth + step);
      if (depth == Tube.depth) {
        _descending = false;
        final lanes = gameRef.view.tube.laneCount;
        lane = (lane + 1 + gameRef.random.nextInt(lanes - 1)) % lanes;
      }
    }
  }
}
