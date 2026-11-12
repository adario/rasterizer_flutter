import 'package:flame/components.dart';

/// A star sprite that falls slowly, half again as fast as Rogue Shooter's
/// stars, and doesn't twinkle.
class StarComponent({super.sprite, super.position, super.size})
    extends SpriteComponent
    with HasGameRef {
  /// Its speed, in world units a second.
  static const speed = 15;

  @override
  void update(double dt) {
    super.update(dt);
    y += dt * speed;
    if (y >= gameRef.size.y) {
      removeFromParent();
    }
  }
}
