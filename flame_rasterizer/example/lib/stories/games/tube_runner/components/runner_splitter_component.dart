import 'package:flame_rasterizer_example/stories/games/tube_runner/components/runner_enemy_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_runner/endless_tube.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/enemy_component.dart';

/// A splitter, which climbs its [lane] toward the ship from [at], as fast as
/// a seeder, without flipping or firing, as Tube Shooter's
/// `SplitterComponent` does.
///
/// When shot, or [splitAhead] of the ship, as Tube Shooter's at the rim, the
/// game splits it into two climbers, which flip onto the lanes on either
/// side.
class RunnerSplitterComponent(
  @override final int lane,
  @override var double at, {
  super.from,
}) extends RunnerEnemyComponent {
  this : super(EnemyKind.splitter, lane);

  /// How far ahead of the ship it splits on its own, along the axis, in tube
  /// units.
  static const splitAhead = 4.0;

  @override
  int get currentLane => lane;

  @override
  TubeMark get mark => (lane: lane, at: at, flip: null);

  @override
  void move(double dt) {
    at -= RunnerEnemyComponent.climbSpeed * dt;
  }
}
