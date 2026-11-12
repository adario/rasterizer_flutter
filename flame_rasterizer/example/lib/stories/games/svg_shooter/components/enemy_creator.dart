import 'package:flame/components.dart';
import 'package:flame_rasterizer_example/stories/games/svg_shooter/components/enemy_component.dart';
import 'package:flame_rasterizer_example/stories/games/svg_shooter/svg_shooter_example.dart';

/// Sends a wave of 5 enemies every [wavePeriod], each of a random kind.
///
/// The waves come a quarter less often than Rogue Shooter's. A game starts
/// with the enemies that would be falling already in the top
/// [firstWaveDepth] of the game, well above the player.
class EnemyCreator() extends TimerComponent with HasGameRef<SvgShooterExample> {
  /// Seconds from a wave to the next: a third longer than Rogue Shooter's
  /// 0.05, so that 75 enemies come each second, not 100.
  static const wavePeriod = 1 / 15;

  /// How far down the first wave goes, as a fraction of the game's height.
  static const firstWaveDepth = 0.2;

  final _halfWidth = EnemyComponent.initialSize.x / 2;

  this : super(period: wavePeriod, repeat: true) {
    timer.onTick = _spawn;
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    createFirstWave();
  }

  /// Adds the waves that would be falling already, down to [firstWaveDepth]
  /// of the game's height.
  ///
  /// The waves are as far apart as an enemy falls in [wavePeriod]. None go
  /// further down, near the player, which starts at the game's center.
  void createFirstWave() {
    final bottom = gameRef.size.y * firstWaveDepth;
    final halfHeight = EnemyComponent.initialSize.y / 2;
    for (
      var y = 0.0;
      y + halfHeight < bottom;
      y += EnemyComponent.speed * wavePeriod
    ) {
      _spawn(y);
    }
  }

  /// Adds a wave at [y], each enemy wholly within the game's width.
  ///
  /// Each enemy's [EnemyComponent.age] is how long it would take to fall
  /// there from the top.
  void _spawn([double y = 0]) {
    final random = gameRef.random;
    final kinds = gameRef.enemyKinds;
    gameRef.enemyGroup.addAll(
      List.generate(
        5,
        (index) => EnemyComponent(
          kinds[random.nextInt(kinds.length)],
          position: Vector2(
            _halfWidth +
                (gameRef.size.x - 2 * _halfWidth) * random.nextDouble(),
            y,
          ),
          age: y / EnemyComponent.speed,
        ),
      ),
    );
  }
}
