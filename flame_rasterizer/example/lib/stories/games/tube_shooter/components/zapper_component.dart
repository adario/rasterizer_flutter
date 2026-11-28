import 'dart:math' as math;

import 'package:flame_rasterizer_example/commons/material.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/enemy_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube.dart';

/// A zapper, which climbs its lane without firing and electrifies it.
///
/// Now and then, it flips onto a neighbouring lane. At the rim, it flips
/// toward the ship. During a pulse, a bolt runs from it along its lane to the
/// rim and destroys the ship if the ship is there. It flashes white just
/// before each pulse. A zapper that arrives too late to flash waits for the
/// next pulse.
class ZapperComponent({
  required super.lane,
  required super.depth,
  super.from,
}) extends EnemyComponent {
  this : super(EnemyKind.zapper);

  /// Seconds until it flips, counted at the first round's pace.
  double _untilFlip = 0;
  bool _white = false;

  /// Whether it flashed white before the current or next pulse.
  bool _warned = false;

  /// Whether its bolt is running along its lane.
  bool get isZapping => _warned && shooter.isPulsing && !isFlipping;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    if (from?.own case (
      :final double untilFlip,
      :final bool white,
      :final bool warned,
    )) {
      _untilFlip = untilFlip;
      _warned = warned;
      _flash(white);
      return;
    }
    _untilFlip = between(shooter.level.zapperFlipPeriod);
  }

  @override
  Record get ownSnapshot =>
      (untilFlip: _untilFlip, white: _white, warned: _warned);

  @override
  bool destroysShip(int shipLane) => isZapping && lane == shipLane;

  @override
  void move(double dt) {
    super.move(dt);
    final level = shooter.level;
    final pace = shooter.pace;
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
      final toward = shooter.towardShip(lane);
      if (toward != 0) {
        flipAside(toward);
      }
    }
    final warning = shooter.isWarning;
    if (warning) {
      _warned = true;
    } else if (!shooter.isPulsing) {
      _warned = false;
    }
    _flash(warning);
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
