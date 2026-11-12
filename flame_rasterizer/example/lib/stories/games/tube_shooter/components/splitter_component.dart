import 'dart:math' as math;

import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/enemy_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube.dart';

/// A splitter, which climbs its lane slowly.
///
/// When shot, or at the rim, it splits into two climbers, which flip onto the
/// lanes on either side.
class SplitterComponent({required super.lane, required super.depth})
    extends EnemyComponent {
  this : super(EnemyKind.splitter);

  @override
  void move(double dt) {
    super.move(dt);
    final level = gameRef.level;
    depth = math.max(
      0,
      depth - dt * gameRef.pace * Tube.depth / level.splitterTime,
    );
    if (depth == 0) {
      gameRef.split(this);
    }
  }
}
