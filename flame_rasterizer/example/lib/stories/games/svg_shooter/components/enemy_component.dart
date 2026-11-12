import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flame_rasterizer/flame_rasterizer.dart';
import 'package:flame_rasterizer_example/commons/example_colors.dart';
import 'package:flame_rasterizer_example/commons/svg_renderers.dart';
import 'package:flame_rasterizer_example/stories/games/svg_shooter/components/explosion_component.dart';
import 'package:flame_rasterizer_example/stories/games/svg_shooter/svg_shooter_example.dart';

/// A kind of enemy: its SVG, whether to turn it by 180° so that it faces
/// down, and whether it swings.
typedef EnemyKind = ({ExampleSvg svg, bool turned, bool swings});

/// An enemy of [kind], which falls down the game and explodes when hit.
///
/// It tints its SVG with one of [ExampleColors.dynamics], at random, and
/// has a passive [SvgHitbox]. An enemy that swings falls straight down at
/// [speed], and swings like a pendulum around its center, by a random angle.
/// Its swing starts [age] seconds in, as the first wave's enemies have been
/// falling that long. Other enemies tilt by a random angle, and fly where
/// they point at a random speed around [speed].
class EnemyComponent(
  final EnemyKind kind, {
  required super.position,
  final double age = 0,
}) extends PositionComponent with HasGameRef<SvgShooterExample> {
  /// The enemies' speed, in world units a second: 10% slower than Rogue
  /// Shooter's 150.
  static const speed = 135;

  /// The most that an enemy that doesn't swing tilts, either way, in whole
  /// degrees.
  static const tiltDegrees = 15;

  /// The most that a tilted enemy's speed differs from [speed], either way,
  /// as a fraction of it.
  static const speedSpread = 0.1;

  /// The least and the most that a swing turns, either way, in whole
  /// degrees.
  static const swingDegrees = (5, 15);

  /// Seconds that a swing takes, from upright to one side, then to the other
  /// side, and back.
  static const swingPeriod = 2.0;

  /// About 15% larger than Rogue Shooter's enemies, which are 25 across. The
  /// SVGs' content fills the full height of their square.
  static final Vector2 initialSize = Vector2.all(29);

  /// The tint of its SVG.
  late final Color color;

  /// Where it flies, and how fast, in world units a second.
  late final Vector2 velocity;

  this
    : super(
        size: initialSize,
        anchor: Anchor.center,
        angle: kind.turned ? math.pi : 0,
      );

  @override
  Future<void> onLoad() async {
    final random = gameRef.random;
    const colors = ExampleColors.dynamics;
    color = colors[random.nextInt(colors.length)];
    final svg = kind.svg.component()..size = size;
    (svg as HasPaint).tint(color);
    addAll([
      svg,
      SvgHitbox(
        kind.svg.outline,
        size: size,
        collisionType: CollisionType.passive,
      ),
    ]);
    if (kind.swings) {
      velocity = Vector2(0, speed.toDouble());
      final (least, most) = swingDegrees;
      final degrees = least + random.nextInt(most - least + 1);
      add(
        RotateEffect.by(
          degrees * math.pi / 180,
          InfiniteEffectController(SineEffectController(period: swingPeriod))
            ..advance(age),
        ),
      );
    } else {
      final degrees = random.nextInt(2 * tiltDegrees + 1) - tiltDegrees;
      final tilt = degrees * math.pi / 180;
      angle += tilt;
      final spread = speedSpread * (2 * random.nextDouble() - 1);
      velocity = Vector2(0, speed * (1 + spread))..rotate(tilt);
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    position.addScaled(velocity, dt);
    // Remove it past the bottom, or once it's wholly out of a side, where a
    // tilted enemy can fly.
    final reach = size.length / 2;
    if (y >= gameRef.size.y || x < -reach || x > gameRef.size.x + reach) {
      removeFromParent();
    }
  }

  /// Explodes as a missile hits it, and scores a point.
  void takeHit() {
    if (_explode(ExplosionKind.missileHit)) {
      gameRef.increaseScore();
    }
  }

  /// Explodes in red as it hits the player, without scoring.
  ///
  /// Returns whether it exploded: once hit, it does nothing.
  bool hitPlayer() => _explode(ExplosionKind.playerHit);

  /// Removes it with an explosion of [kind], and returns true, unless it's
  /// removed already. A missile and the player can hit it in the same frame.
  bool _explode(ExplosionKind kind) {
    if (isRemoving || isRemoved) {
      return false;
    }
    removeFromParent();
    gameRef.explosionGroup.add(ExplosionComponent(kind, position: position));
    return true;
  }
}
