import 'dart:math' as math;

import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/enemy_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube.dart';

/// A splitter, which climbs its lane slowly.
///
/// When it's shot or reaches the rim, it splits into two climbers that flip
/// onto the lanes on either side.
class SplitterComponent({
  required super.lane,
  required super.depth,
  super.from,
}) extends EnemyComponent {
  this : super(EnemyKind.splitter);

  @override
  void move(double dt) {
    super.move(dt);
    final level = shooter.level;
    depth = math.max(
      0,
      depth - dt * shooter.pace * Tube.depth / level.splitterTime,
    );
    if (depth == 0) {
      shooter.split(this);
    }
  }
}
