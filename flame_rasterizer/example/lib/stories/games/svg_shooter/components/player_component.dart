import 'dart:math' as math;

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flame_rasterizer/flame_rasterizer.dart';
import 'package:flame_rasterizer_example/commons/material.dart' show Colors;
import 'package:flame_rasterizer_example/commons/svg_renderers.dart';
import 'package:flame_rasterizer_example/stories/games/svg_shooter/components/enemy_component.dart';
import 'package:flame_rasterizer_example/stories/games/svg_shooter/components/explosion_component.dart';
import 'package:flame_rasterizer_example/stories/games/svg_shooter/components/missile_component.dart';
import 'package:flame_rasterizer_example/stories/games/svg_shooter/svg_shooter_example.dart';

/// The player's spaceship, which draws [svg] and collides with an
/// [SvgHitbox] in the SVG's shape.
///
/// It fires a volley of missiles every [firePeriod] while the game is dragged
/// or the fire key is held. Each enemy that hits it takes [hitDamage] off its
/// [health]. After [healDelay] without a hit, its health comes back at
/// [healRate] a second. At 0, it blows up, turns red and fades out, and then
/// the game is over.
class PlayerComponent(final ExampleSvg svg)
    extends PositionComponent
    with HasGameRef<SvgShooterExample>, CollisionCallbacks {
  /// About 15% narrower than Rogue Shooter's player, which is 75 wide. The
  /// SVG's viewBox, 64 by 42, fits the spaceship and its stroke, so the
  /// height keeps its proportions.
  static final Vector2 initialSize = Vector2(64, 42);

  /// Its full health, in percent.
  static const maxHealth = 100;

  /// The health, in percent, that each hit takes off.
  static const hitDamage = 2;

  /// The health, in percent, that comes back each second after [healDelay].
  static const healRate = 2;

  /// Seconds without a hit before its health starts to come back.
  static const healDelay = 3.0;

  /// How fast the keys move it, in world units a second.
  static const keySpeed = 400.0;

  /// Seconds from a volley to the next: three times Rogue Shooter's 0.05, so
  /// that the volleys stay apart.
  static const firePeriod = 0.15;

  /// Seconds it takes to turn red once destroyed, as long as the explosion's
  /// flash.
  static const reddenTime = 0.25;

  /// Seconds it takes to fade out once destroyed.
  static const fadeTime = 2.0;

  /// Fires a volley every [firePeriod] while it runs.
  late TimerComponent missileCreator;
  late final PositionComponent _ship;
  late final SvgHitbox _hitbox;

  /// Its health in percent, from [maxHealth] down to 0.
  int health = maxHealth;

  /// Seconds since the last hit, less those that have healed it.
  double _sinceHit = 0;

  /// Seconds since the last volley. It starts at [firePeriod], so that the
  /// first volley fires at once.
  double _sinceVolley = firePeriod;

  /// Whether its health ran out. It then neither moves, fires nor gets hit
  /// until a new game.
  bool get isDestroyed => _isDestroyed;
  bool _isDestroyed = false;

  this : super(size: initialSize, anchor: Anchor.center);

  @override
  Future<void> onLoad() async {
    position = gameRef.size / 2;
    addAll([
      _ship = svg.component()..size = size,
      _hitbox = SvgHitbox(svg.outline, size: size),
      missileCreator = TimerComponent(
        period: firePeriod,
        repeat: true,
        autoStart: false,
        onTick: _createMissile,
      ),
    ]);
  }

  @override
  void update(double dt) {
    super.update(dt);
    _sinceVolley += dt;
    if (_isDestroyed) {
      return;
    }
    _move(gameRef.keyDirection, dt);
    _sinceHit += dt;
    // One percent back every 1 / healRate seconds, once healDelay has passed.
    while (health < maxHealth && _sinceHit >= healDelay + 1 / healRate) {
      health++;
      _sinceHit -= 1 / healRate;
    }
  }

  /// Moves it along [direction] at [keySpeed], within the play area, which is
  /// the game's size.
  ///
  /// A drag can take it out of the play area. From there, the keys only move
  /// it toward the play area.
  void _move(Vector2 direction, double dt) {
    if (direction.isZero()) {
      return;
    }
    final distance = keySpeed * dt;
    final half = size / 2;
    x = _within(x + direction.x * distance, x, half.x, gameRef.size.x - half.x);
    y = _within(y + direction.y * distance, y, half.y, gameRef.size.y - half.y);
  }

  /// Clamps [value] between [min] and [max], widened to take in [from] when
  /// it's outside them.
  static double _within(double value, double from, double min, double max) =>
      value.clamp(math.min(from, min), math.max(from, max));

  /// The angles of a volley's missiles: Rogue Shooter's, without its leftmost
  /// and rightmost.
  static const _missileAngles = [0.3, 0.0, -0.3];

  /// Fires a volley from the top of the spaceship.
  void _createMissile() {
    _sinceVolley = 0;
    gameRef.missileGroup.addAll(
      _missileAngles.map(
        (angle) => MissileComponent(
          gameRef.missileSvg,
          position: position + Vector2(0, -size.y / 2),
          angle: angle,
        ),
      ),
    );
  }

  /// Starts firing, unless it's destroyed or firing already.
  ///
  /// It fires a volley at once, unless the last was less than [firePeriod]
  /// ago, and then one every [firePeriod]. So taps don't fire faster than a
  /// drag.
  void beginFire() {
    final timer = missileCreator.timer;
    if (_isDestroyed || timer.isRunning()) {
      return;
    }
    if (_sinceVolley >= firePeriod) {
      _createMissile();
    }
    // Time the next volley from the last one.
    timer
      ..start()
      ..update(_sinceVolley);
  }

  void stopFire() {
    missileCreator.timer.pause();
  }

  /// Takes [hitDamage] off its [health], and destroys it at 0.
  void takeHit() {
    if (_isDestroyed) {
      return;
    }
    _sinceHit = 0;
    health = math.max(0, health - hitDamage);
    if (health == 0) {
      _destroy();
    }
  }

  /// Blows it up in red, and turns it red as it fades out. Then the game is
  /// over.
  void _destroy() {
    _isDestroyed = true;
    stopFire();
    _hitbox.collisionType = CollisionType.inactive;
    gameRef.explosionGroup.add(
      ExplosionComponent(ExplosionKind.playerDestroyed, position: position),
    );
    _ship.addAll([
      ColorEffect(Colors.red, EffectController(duration: reddenTime)),
      OpacityEffect.fadeOut(
        EffectController(duration: fadeTime),
        onComplete: gameRef.gameOver,
      ),
    ]);
  }

  /// Puts it back as at the start of a game: at the center, not faded, with
  /// full health and not firing.
  void reset() {
    position = gameRef.size / 2;
    health = maxHealth;
    _sinceHit = 0;
    _sinceVolley = firePeriod;
    _isDestroyed = false;
    _hitbox.collisionType = CollisionType.active;
    (_ship as HasPaint)
      ..opacity = 1
      ..paint.colorFilter = null;
    stopFire();
  }

  @override
  void onCollisionStart(
    List<Vector2> intersectionPoints,
    PositionComponent other,
  ) {
    super.onCollisionStart(intersectionPoints, other);
    if (other is EnemyComponent && other.hitPlayer()) {
      takeHit();
    }
  }
}
