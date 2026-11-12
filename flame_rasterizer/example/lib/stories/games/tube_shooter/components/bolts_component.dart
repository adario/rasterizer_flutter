import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/zapper_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/shapes.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube_shooter_example.dart';

/// Draws the zappers' bolts while they zap, each down its zapper's lane to the
/// rim.
///
/// All the bolts make one path. On every frame of a pulse, this makes the path
/// again, with a new component in the game's tube group, unless the world is
/// still and the view hasn't changed.
class BoltsComponent() extends Component with HasGameRef<TubeShooterExample> {
  this : super(priority: 10);

  /// For the bolts' zigzags, apart from [TubeShooterExample.random], so that
  /// drawing doesn't change the game's random sequence.
  final _random = math.Random(0);

  PathComponent? _bolts;
  int _version = -1;

  @override
  void update(double dt) {
    super.update(dt);
    final game = gameRef;
    final view = game.view;
    final bolts = [
      for (final enemy in game.enemies)
        if (enemy is ZapperComponent && enemy.isZapping)
          (enemy.lane, enemy.depth),
    ];
    if (bolts.isEmpty) {
      _bolts = game.replacePath(_bolts, null, TubeColors.bolts);
      return;
    }
    if (dt == 0 && view.version == _version && _bolts != null) {
      return;
    }
    _version = view.version;
    _bolts = game.replacePath(
      _bolts,
      view.boltsPath(bolts, _random),
      TubeColors.bolts,
      priority: 3,
    );
  }
}
