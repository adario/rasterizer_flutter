import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/lane_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/shapes.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube.dart';

/// A shot from the ship, which flies down its lane and is gone at the far end.
class ShotComponent({required super.lane, required super.depth})
    extends LaneComponent {
  this : super(Shapes.shot, TubeColors.shot);

  /// The seconds a shot takes to cross the tube.
  static const crossTime = 0.5;

  @override
  void move(double dt) {
    depth += dt * Tube.depth / crossTime;
    if (depth >= Tube.depth) {
      gameRef.discard(this);
    }
  }
}

/// A shot from an enemy, which flies up its lane in the level's
/// `enemyShotTime`.
///
/// The game removes it at the rim, where it destroys the ship if the ship is
/// in its lane.
class EnemyShotComponent({required super.lane, required super.depth})
    extends LaneComponent {
  this : super(Shapes.enemyShot, TubeColors.shot);

  @override
  void move(double dt) {
    final speed = gameRef.pace * Tube.depth / gameRef.level.enemyShotTime;
    depth -= dt * speed;
  }
}
