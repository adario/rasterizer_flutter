import 'package:flame_rasterizer_example/stories/games/tube_runner/components/runner_enemy_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_runner/endless_tube.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/enemy_component.dart';

/// A seeder that climbs its lane toward the ship and lays its [spike] behind
/// it, as Tube Shooter's `SeederComponent` does.
///
/// The spike stays where it is laid, so it comes at the ship as fast as the
/// tube does, and the seeder comes faster. A shot destroys the seeder and
/// leaves its spike.
class RunnerSeederComponent(final Spike spike, {super.from})
    extends RunnerEnemyComponent {
  this : super(EnemyKind.seeder, spike.lane);

  /// It sits at its spike's near end.
  @override
  double get at => spike.near;

  @override
  int get lane => spike.lane;

  @override
  int get currentLane => spike.lane;

  /// Its spike's place among the game's spikes.
  @override
  Record get ownSnapshot => (spike: runner.spikes.indexOf(spike));

  @override
  TubeMark get mark =>
      (lane: spike.lane, at: spike.near, flip: null, across: null);

  /// Climbs its lane, laying the spike up to where it gets.
  @override
  void move(double dt) {
    spike.near -= RunnerEnemyComponent.climbSpeed * dt;
  }
}
