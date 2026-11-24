import 'package:flame_rasterizer_example/stories/games/tube_runner/components/runner_enemy_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_runner/endless_tube.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/enemy_component.dart';

/// A seeder, which climbs its lane toward the ship and lays its [spike]
/// behind it, as Tube Shooter's `SeederComponent` does.
///
/// The spike stays where it's laid, so it comes at the ship as the tube does,
/// and the seeder faster. A shot destroys the seeder, and leaves its spike.
class RunnerSeederComponent(final Spike spike) extends RunnerEnemyComponent {
  this : super(EnemyKind.seeder, spike.lane);

  /// At its spike's near end.
  @override
  double get at => spike.near;

  @override
  int get currentLane => spike.lane;

  @override
  TubeMark get mark => (lane: spike.lane, at: spike.near, flip: null);

  /// Climbs its lane, laying the spike to where it gets.
  @override
  void move(double dt) {
    spike.near -= RunnerEnemyComponent.climbSpeed * dt;
  }
}
