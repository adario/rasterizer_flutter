import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/particles.dart';
import 'package:flame_rasterizer_example/commons/material.dart';
import 'package:flame_rasterizer_example/stories/games/svg_shooter/components/enemy_component.dart';
import 'package:flame_rasterizer_example/stories/games/svg_shooter/components/player_component.dart';
import 'package:flame_rasterizer_example/stories/games/svg_shooter/svg_shooter_example.dart';

/// What blows up: an enemy that a missile hit, an enemy that hit the player,
/// or the player once its health runs out.
enum ExplosionKind() {
  missileHit,
  playerHit,
  playerDestroyed,
}

/// The Explosion of Flame's particles example, played once: a flash and
/// debris.
///
/// Its distances scale so that it's twice as wide as what blows up, as in
/// Rogue Shooter, while the debris' dots keep their sizes. A missile's hit
/// has the particles example's colors, from white to yellows and reds. A hit
/// on the player, and the player's own explosion, go from white to reds. It
/// removes itself once both the flash and the debris are done.
class ExplosionComponent(final ExplosionKind kind, {super.position})
    extends PositionComponent
    with HasGameRef<SvgShooterExample> {
  /// The width of an explosion of [kind]: twice that of what blows up, as
  /// Rogue Shooter's explosions, 50 wide, are twice its enemies' width.
  static double acrossOf(ExplosionKind kind) =>
      2 *
      switch (kind) {
        ExplosionKind.missileHit ||
        ExplosionKind.playerHit => EnemyComponent.initialSize.x,
        ExplosionKind.playerDestroyed => PlayerComponent.initialSize.x,
      };

  /// The least and the most speed of the particles example's debris.
  static const _debrisSpeed = (40.0, 300.0);

  /// The longest life of the particles example's debris, in seconds.
  static const _debrisLife = 1.4;

  /// The drag of the particles example's debris.
  static const _drag = 2.5;

  /// How far the fastest debris goes in its longest life, slowed by its drag:
  /// about 116 in the particles example.
  static final _reach =
      _debrisSpeed.$2 / _drag * (1 - math.exp(-_drag * _debrisLife));

  /// The colors of the red explosions, for the player.
  static const _redFlash = [Colors.white, Colors.redAccent];
  static final _redDebris = [
    Colors.white,
    Colors.redAccent,
    Colors.red,
    Colors.red.shade900,
  ];

  /// Each kind's flash and debris.
  static final _emitters = {
    ExplosionKind.missileHit: _emittersOf(
      ExplosionKind.missileHit,
      flash: const [Colors.white, Colors.orangeAccent],
      debris: const [
        Colors.white,
        Colors.yellowAccent,
        Colors.deepOrange,
        Colors.red,
      ],
    ),
    ExplosionKind.playerHit: _emittersOf(
      ExplosionKind.playerHit,
      flash: _redFlash,
      debris: _redDebris,
    ),
    ExplosionKind.playerDestroyed: _emittersOf(
      ExplosionKind.playerDestroyed,
      flash: _redFlash,
      debris: _redDebris,
    ),
  };

  /// Creates the flash and the debris of an explosion of [kind], which go
  /// through the colors in [flash] and [debris] as they age.
  ///
  /// Distances scale by about 0.25 for an enemy's explosion. Unlike the
  /// particles example's, the emitters don't loop and have no duration: each
  /// is done once its particles are. Each has room for just the particles of
  /// its one burst.
  static (ParticleEmitter, ParticleEmitter) _emittersOf(
    ExplosionKind kind, {
    required List<Color> flash,
    required List<Color> debris,
  }) {
    final scale = acrossOf(kind) / 2 / _reach;
    return (
      ParticleEmitter(
        maxParticles: 1,
        bursts: const [EmitterBurst(0, 1)],
        lifespan: (0.25, 0.25),
        size: (60 * scale, 60 * scale),
        scaleOverLife: ParticleCurve(0.3, 2.2, curve: Curves.easeOutExpo),
        colorOverLife: ColorRamp(flash),
        opacityOverLife: ParticleCurve(1, 0),
      ),
      ParticleEmitter(
        maxParticles: 250,
        bursts: const [EmitterBurst(0, 250)],
        lifespan: (0.5, _debrisLife),
        speed: (_debrisSpeed.$1 * scale, _debrisSpeed.$2 * scale),
        drag: _drag,
        size: (1.5, 5),
        scaleOverLife: ParticleCurve(1, 0, curve: Curves.easeOut),
        colorOverLife: ColorRamp(debris),
      ),
    );
  }

  @override
  Future<void> onLoad() async {
    final renderer = gameRef.explosionRenderer;
    final (flash, debris) = _emitters[kind]!;
    addAll([
      ParticleEmitterComponent(
        emitter: flash,
        renderer: renderer,
        random: gameRef.random,
      ),
      ParticleEmitterComponent(
        emitter: debris,
        renderer: renderer,
        random: gameRef.random,
      ),
    ]);
  }

  @override
  void onChildrenChanged(Component child, ChildrenChangeType type) {
    super.onChildrenChanged(child, type);
    if (type == ChildrenChangeType.removed && children.isEmpty) {
      removeFromParent();
    }
  }
}
