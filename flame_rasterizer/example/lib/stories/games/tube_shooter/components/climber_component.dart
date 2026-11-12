import 'dart:math' as math;

import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/enemy_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube.dart';

/// A climber, which climbs its lane and fires up it.
///
/// Now and then, it flips onto a neighbouring lane. At the rim, it flips
/// toward the ship, and destroys it once in the ship's lane.
class ClimberComponent({required super.lane, required super.depth})
    extends EnemyComponent {
  this : super(EnemyKind.climber);

  /// Seconds until it flips, at the first round's pace.
  double _untilFlip = 0;

  /// Seconds until it fires, at the first round's pace.
  double _untilFire = 0;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    final level = gameRef.level;
    _untilFlip = between(level.flipPeriod);
    _untilFire = between(level.firePeriod);
  }

  @override
  bool destroysShip(int shipLane) =>
      depth == 0 && !isFlipping && lane == shipLane;

  @override
  void move(double dt) {
    super.move(dt);
    final level = gameRef.level;
    final pace = gameRef.pace;
    _untilFlip -= dt * pace;
    if (depth > 0) {
      depth = math.max(0, depth - dt * pace * Tube.depth / level.climberTime);
      if (depth == 0) {
        _untilFlip = math.min(_untilFlip, level.rimFlipPeriod);
        return;
      }
      _untilFire -= dt * pace;
      if (_untilFire <= 0) {
        _untilFire = between(level.firePeriod);
        gameRef.fireAt(this);
      }
      if (_untilFlip <= 0 && !isFlipping) {
        _untilFlip = between(level.flipPeriod);
        flipAside(gameRef.random.nextBool() ? 1 : -1);
      }
    } else if (_untilFlip <= 0 && !isFlipping) {
      _untilFlip = level.rimFlipPeriod;
      final toward = gameRef.towardShip(lane);
      if (toward != 0) {
        flipAside(toward);
      }
    }
  }
}
