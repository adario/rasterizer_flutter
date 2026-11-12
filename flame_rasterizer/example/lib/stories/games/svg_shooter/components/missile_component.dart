import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame_rasterizer/flame_rasterizer.dart';

import 'package:flame_rasterizer_example/commons/svg_renderers.dart';
import 'package:flame_rasterizer_example/stories/games/svg_shooter/components/enemy_component.dart';
import 'package:flame_rasterizer_example/stories/games/svg_shooter/components/player_component.dart';

/// A missile that draws [svg] and flies along its angle, as Rogue Shooter's
/// bullets do.
///
/// It collides with an [SvgHitbox] in the SVG's shape, and destroys the
/// first enemy it hits.
class MissileComponent(
  final ExampleSvg svg, {
  required super.position,
  super.angle,
}) extends PositionComponent with HasGameRef, CollisionCallbacks {
  /// Its speed, in world units a second.
  static const speed = 500.0;

  /// In the same ratio to the player's width as Rogue Shooter's bullets, 20
  /// high, to its player, 75 wide. The SVG's content fills the full height of
  /// its square.
  static final Vector2 initialSize = Vector2.all(
    PlayerComponent.initialSize.x * 20 / 75,
  );

  late final Vector2 velocity;

  this : super(size: initialSize, anchor: Anchor.center);

  @override
  Future<void> onLoad() async {
    addAll([svg.component()..size = size, SvgHitbox(svg.outline, size: size)]);
    velocity = Vector2(0, -1)
      ..rotate(angle)
      ..scale(speed);
  }

  @override
  void onCollisionStart(
    List<Vector2> intersectionPoints,
    PositionComponent other,
  ) {
    super.onCollisionStart(intersectionPoints, other);
    // Hit only the first of the enemies that it touches in a frame.
    if (isRemoving) {
      return;
    }
    if (other is EnemyComponent) {
      other.takeHit();
      removeFromParent();
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    position.addScaled(velocity, dt);

    if (position.y < 0 ||
        position.x > gameRef.size.x ||
        position.x + size.x < 0) {
      removeFromParent();
    }
  }
}
