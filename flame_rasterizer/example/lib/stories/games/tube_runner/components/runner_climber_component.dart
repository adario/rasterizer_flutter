import 'package:flame_rasterizer_example/stories/games/tube_runner/components/runner_enemy_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_runner/tube_runner_example.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/enemy_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/level.dart';

/// A climber, which climbs its [lane] toward the ship from [at], flips now
/// and then, and fires down its lane, as Tube Shooter's `ClimberComponent`
/// does at its first level's pace, but as fast as a seeder.
///
/// It fires with [TubeRunnerExample.fireFrom].
class RunnerClimberComponent(int lane, double at)
    extends RunnerFlipperComponent {
  this : super(EnemyKind.climber, lane, at);

  @override
  Range get flipPeriod => RunnerFlipperComponent.level.flipPeriod;

  /// Seconds until it fires.
  late double _untilFire = between(RunnerFlipperComponent.level.firePeriod);

  @override
  void move(double dt) {
    super.move(dt);
    _untilFire -= dt;
    if (_untilFire <= 0) {
      _untilFire = between(RunnerFlipperComponent.level.firePeriod);
      gameRef.fireFrom(this);
    }
  }
}
