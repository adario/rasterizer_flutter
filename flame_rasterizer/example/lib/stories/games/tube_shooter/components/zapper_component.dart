import 'dart:math' as math;

import 'package:flame_rasterizer_example/commons/material.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/enemy_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube.dart';

/// A zapper, which climbs its lane without firing, and electrifies it.
///
/// Now and then, it flips onto a neighbouring lane. At the rim, it flips
/// toward the ship. While the zappers pulse, a bolt runs from it down its lane
/// to the rim, and destroys the ship there. Just before a pulse, it flashes
/// white.
class ZapperComponent({required super.lane, required super.depth})
    extends EnemyComponent {
  this : super(EnemyKind.zapper);

  /// Seconds until it flips, at the first round's pace.
  double _untilFlip = 0;
  bool _white = false;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _untilFlip = between(gameRef.level.zapperFlipPeriod);
  }

  @override
  bool destroysShip(int shipLane) =>
      gameRef.isPulsing && !isFlipping && lane == shipLane;

  @override
  void move(double dt) {
    super.move(dt);
    final level = gameRef.level;
    final pace = gameRef.pace;
    _untilFlip -= dt * pace;
    if (depth > 0) {
      depth = math.max(0, depth - dt * pace * Tube.depth / level.zapperTime);
      if (depth == 0) {
        _untilFlip = math.min(_untilFlip, level.zapperRimFlipPeriod);
      } else if (_untilFlip <= 0 && !isFlipping) {
        _untilFlip = between(level.zapperFlipPeriod);
        flipAside(gameRef.random.nextBool() ? 1 : -1);
      }
    } else if (_untilFlip <= 0 && !isFlipping) {
      _untilFlip = level.zapperRimFlipPeriod;
      final toward = gameRef.towardShip(lane);
      if (toward != 0) {
        flipAside(toward);
      }
    }
    _flash(gameRef.isWarning);
  }

  /// Tints it white, or clears the tint. A tint doesn't import its shape
  /// again.
  void _flash(bool white) {
    if (white == _white) {
      return;
    }
    _white = white;
    if (white) {
      drawing.tint(Colors.white);
    } else {
      drawing.paint.colorFilter = null;
    }
  }
}
