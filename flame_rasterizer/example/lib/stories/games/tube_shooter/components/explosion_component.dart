import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/shapes.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube_shooter_example.dart';

/// A burst of rays in [color], placed, turned and scaled as what it destroyed.
///
/// Over [duration] seconds, it grows to twice its size and its rays fade out.
/// Unless it's deeper than [farDepth], 8 more rays, between those, fly out
/// from its middle for twice as long, fading out over the second half, in
/// [rayColor]. Then it removes itself.
class ExplosionComponent({
  required super.position,
  required super.angle,
  required super.scale,

  /// How deep in the tube it is.
  required final double depth,
  final Color color = TubeColors.explosion,

  /// The colour of its flying rays, such as that of what it destroyed, or
  /// null for [color].
  final Color? rayColor,
}) extends PositionComponent with HasGameRef<TubeShooterExample> {
  static const duration = 0.5;

  /// The depth past which no rays fly out: 85% of the way to the far end.
  static const farDepth = 0.85 * Tube.depth;

  /// How fast the flying rays move away from the middle, in the burst's own
  /// units a second, which grow with it.
  static const flySpeed = 0.5;

  /// The components that draw its burst and its flying rays.
  final _drawings = <PathComponent>[];

  @override
  Future<void> onLoad() async {
    _drawings.add(
      gameRef.shapeComponent(Shapes.burst, color)
        ..add(OpacityEffect.fadeOut(EffectController(duration: duration))),
    );
    final flies = depth <= farDepth;
    if (flies) {
      for (var i = 0; i < 8; i++) {
        // Each ray turns about the burst's middle, then moves away from it.
        final angle = i * math.pi / 4;
        final away = Vector2(1, 0)..rotate(angle + math.pi / 8);
        final ray = gameRef.shapeComponent(Shapes.ray, color)
          ..angle = angle
          ..add(
            MoveEffect.by(
              away * (flySpeed * 2 * duration),
              EffectController(duration: 2 * duration),
            ),
          )
          ..add(
            OpacityEffect.fadeOut(
              EffectController(duration: duration, startDelay: duration),
            ),
          );
        // A tint, unlike a paint of another colour, shares the import of the
        // ray in [color].
        if (rayColor case final tint?) {
          ray.tint(tint);
        }
        _drawings.add(ray);
      }
    }
    addAll(_drawings);
    add(ScaleEffect.by(Vector2.all(2), EffectController(duration: duration)));
    add(RemoveEffect(delay: flies ? 2 * duration : duration));
  }

  @override
  void update(double dt) {
    super.update(dt);
    _drawings.forEach(gameRef.keepStroke);
  }
}
