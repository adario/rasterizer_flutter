import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flame_rasterizer_example/stories/games/tube_runner/components/tube_placed.dart';
import 'package:flame_rasterizer_example/stories/games/tube_runner/endless_tube.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/shapes.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube_host.dart';

/// A burst of rays in [color], placed, turned and scaled as what it destroyed,
/// as Tube Shooter's `ExplosionComponent` is, with the same shapes and times.
///
/// Over [duration] seconds, it grows to twice its size and its rays fade out.
/// 8 more rays, between those, fly out from its middle for twice as long,
/// fading out over the second half, in [rayColor]. Then it removes itself,
/// after [lifetime].
class RunnerExplosionComponent({
  super.position,
  super.angle,
  super.scale,
  final Color color = TubeColors.explosion,

  /// The colour of its flying rays, such as that of what it destroyed, or
  /// null for [color].
  final Color? rayColor,
}) extends PositionComponent with HasGameRef<TubeHost> {
  static const duration = 0.5;

  /// How long it shows, in seconds.
  static const lifetime = 2 * duration;

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
    addAll(_drawings);
    add(ScaleEffect.by(Vector2.all(2), EffectController(duration: duration)));
    add(RemoveEffect(delay: lifetime));
  }

  @override
  void update(double dt) {
    super.update(dt);
    _drawings.forEach(gameRef.keepStroke);
  }
}

/// A [RunnerExplosionComponent] at [mark], which stays there as the tube
/// flies, and the game places with [placeAt] where the tube says it shows.
class PlacedExplosionComponent(
  @override final TubeMark mark, {
  final Color? rayColor,
}) extends PositionComponent with HasVisibility, TubePlaced {
  @override
  Future<void> onLoad() async {
    add(RunnerExplosionComponent(rayColor: rayColor));
    add(RemoveEffect(delay: RunnerExplosionComponent.lifetime));
  }
}
