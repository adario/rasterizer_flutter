import 'package:flame_rasterizer_example/stories/games/tube_runner/components/runner_enemy_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_runner/endless_tube.dart';
import 'package:flame_rasterizer_example/stories/games/tube_runner/tube_runner_example.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/enemy_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/level.dart';

/// A climber, which climbs its [lane] toward the ship from [at], and fires
/// down it, as Tube Shooter's `ClimberComponent` does at its first level's
/// pace, but as fast as a seeder.
///
/// Now and then, it flips onto a neighbouring lane, as Tube Shooter's does:
/// it turns about the corner the two lanes share, through the inside of the
/// tube. It fires with [TubeRunnerExample.fireFrom].
class RunnerClimberComponent(var int lane, @override var double at)
    extends RunnerEnemyComponent {
  this : super(EnemyKind.climber, lane);

  /// The pace of Tube Shooter's first level, which it flips and fires at.
  static final _level = levels.first;

  /// The lane it flips onto, if it's flipping, how far through the flip it
  /// is, from 0 to 1, and the angle the whole flip turns by.
  int? _flipTo;
  double _flipProgress = 0;
  double _flipAngle = 0;

  /// Seconds until it flips, and until it fires.
  late double _untilFlip = _between(_level.flipPeriod);
  late double _untilFire = _between(_level.firePeriod);

  /// Halfway through a flip, it's in the lane it flips to, as in Tube
  /// Shooter.
  @override
  int get currentLane {
    final to = _flipTo;
    return to != null && _flipProgress >= 0.5 ? to : lane;
  }

  @override
  TubeMark get mark => (
    lane: lane,
    at: at,
    flip: switch (_flipTo) {
      final to? => (to: to, turn: _flipAngle * _flipProgress),
      null => null,
    },
  );

  @override
  void move(double dt) {
    at -= RunnerEnemyComponent.climbSpeed * dt;
    if (_flipTo case final to?) {
      _flipProgress += dt / _level.flipTime;
      if (_flipProgress >= 1) {
        lane = to;
        _flipTo = null;
      }
    }
    _untilFlip -= dt;
    if (_untilFlip <= 0 && _flipTo == null) {
      _untilFlip = _between(_level.flipPeriod);
      _flipAside(gameRef.random.nextBool() ? 1 : -1);
    }
    _untilFire -= dt;
    if (_untilFire <= 0) {
      _untilFire = _between(_level.firePeriod);
      gameRef.fireFrom(this);
    }
  }

  /// Starts flipping onto the next lane on [side], 1 or -1.
  void _flipAside(int side) {
    final tube = gameRef.tube;
    final to = (tube.neighbour(lane, side) ?? tube.neighbour(lane, -side))!;
    _flipTo = to;
    _flipProgress = 0;
    _flipAngle = tube.flipAngle(lane, to);
  }

  /// Returns a random time within [range].
  double _between(Range range) =>
      range.least + (range.most - range.least) * gameRef.random.nextDouble();
}
