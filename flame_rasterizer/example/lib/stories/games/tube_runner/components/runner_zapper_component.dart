import 'package:flame_rasterizer_example/commons/material.dart';
import 'package:flame_rasterizer_example/stories/games/tube_runner/components/runner_enemy_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_runner/runner_mode.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/enemy_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/level.dart';

/// A zapper, which climbs its [lane] toward the ship from [at] without
/// firing, flips now and then, and electrifies its lane, as Tube Shooter's
/// `ZapperComponent` does at its first level's pace, but as fast as a seeder.
///
/// While the zappers pulse, as [RunnerMode.isPulsing] says, a bolt
/// runs from it down its lane to the ship's ring, and destroys the ship
/// there. Just before a pulse, it flashes white. One that comes too late to
/// flash, or flips, waits for the next pulse.
class RunnerZapperComponent(int lane, double at, {super.from})
    extends RunnerFlipperComponent {
  this : super(EnemyKind.zapper, lane, at);

  @override
  Range get flipPeriod => RunnerFlipperComponent.level.zapperFlipPeriod;

  /// Whether it's tinted white. It tints itself again as it updates, as the
  /// pulse says.
  bool _white = false;

  /// Whether it flashed white before the pulse coming or going on.
  late bool _warned = switch (from?.own) {
    (:final bool warned) => warned,
    _ => false,
  };

  @override
  Record get ownSnapshot => (warned: _warned);

  /// Whether its bolt runs down its lane now.
  bool get isZapping => _warned && runner.isPulsing && !isFlipping;

  @override
  void move(double dt) {
    super.move(dt);
    final warning = runner.isWarning;
    if (warning) {
      _warned = true;
    } else if (!runner.isPulsing) {
      _warned = false;
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    _flash(runner.isWarning);
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
