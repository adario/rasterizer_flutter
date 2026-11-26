import 'package:flame_rasterizer_example/stories/games/tube_runner/components/runner_enemy_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_runner/runner_mode.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/enemy_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/level.dart';

/// A climber, which climbs its [lane] toward the ship from [at], flips now
/// and then, and fires down its lane, as Tube Shooter's `ClimberComponent`
/// does at its first level's pace, but as fast as a seeder.
///
/// It fires with [RunnerMode.fireFrom].
class RunnerClimberComponent(
  int lane,
  double at, {
  super.flashes,
  super.from,
}) extends RunnerFlipperComponent {
  this : super(EnemyKind.climber, lane, at);

  @override
  Range get flipPeriod => RunnerFlipperComponent.level.flipPeriod;

  /// Seconds until it fires, once it picked them, as it first climbed.
  late double? _untilFire = switch (from?.own) {
    (:final double? untilFire) => untilFire,
    _ => null,
  };

  @override
  Record get ownSnapshot => (untilFire: _untilFire);

  @override
  void move(double dt) {
    super.move(dt);
    final period = RunnerFlipperComponent.level.firePeriod;
    var untilFire = (_untilFire ?? between(period)) - dt;
    if (untilFire <= 0) {
      untilFire = between(period);
      runner.fireFrom(this);
    }
    _untilFire = untilFire;
  }
}
