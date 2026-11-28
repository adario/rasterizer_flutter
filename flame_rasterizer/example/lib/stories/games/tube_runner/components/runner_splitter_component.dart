import 'package:flame_rasterizer_example/stories/games/tube_runner/components/runner_enemy_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_runner/endless_tube.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/enemy_component.dart';

/// A splitter that climbs its [lane] toward the ship from [at] as fast as a
/// seeder, without flipping or firing, as Tube Shooter's `SplitterComponent`
/// does.
///
/// When it is shot, or gets within [splitAhead] of the ship, the game splits
/// it into two climbers that flip onto the lanes on either side. Tube
/// Shooter's splitter splits at the rim instead.
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
  TubeMark get mark => (lane: lane, at: at, flip: null, across: null);

  @override
  void move(double dt) {
    at -= RunnerEnemyComponent.climbSpeed * dt;
  }
}
