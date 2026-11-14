part of 'svg_shooter_example.dart';

/// What a game for another renderer goes on from: the score, the player, the
/// seconds since the last wave, and the enemies and the missiles, where they
/// are.
typedef SvgShooterSnapshot = ({
  int score,
  PlayerSnapshot? player,
  double? sinceWave,
  List<({int kind, Vector2 position, double age, EnemyPicks picks})> enemies,
  List<({Vector2 position, double angle})> missiles,
});

/// Takes a [SvgShooterExample]'s snapshot, and goes on from one.
///
/// The explosions and the stars start again in the new game, and so do the
/// keys and the drags, which the new game hasn't seen go down.
extension SvgShooterSnapshots on SvgShooterExample {
  /// What a game for another renderer goes on from.
  ///
  /// It leaves out what hasn't loaded yet, such as the enemies of a wave
  /// that came at this frame.
  SvgShooterSnapshot get snapshot => (
    score: score,
    player: player.isLoaded ? player.snapshot : null,
    sinceWave: _enemyCreator.isLoaded ? _enemyCreator.timer.current : null,
    enemies: [
      for (final enemy in enemyGroup.children.whereType<EnemyComponent>())
        if (enemy.isLoaded)
          (
            kind: enemyKinds.indexOf(enemy.kind),
            position: enemy.position.clone(),
            age: enemy.age,
            picks: enemy.picks,
          ),
    ],
    missiles: [
      for (final missile in missileGroup.children.whereType<MissileComponent>())
        if (missile.isLoaded)
          (position: missile.position.clone(), angle: missile.angle),
    ],
  );

  /// Puts back the snapshot's score, and its enemies and missiles, where they
  /// were.
  void _restoreEnemiesAndMissiles() {
    if (_from case final from?) {
      score = from.score;
      enemyGroup.addAll([
        for (final enemy in from.enemies)
          EnemyComponent(
            enemyKinds[enemy.kind],
            position: enemy.position,
            age: enemy.age,
            from: enemy.picks,
          ),
      ]);
      missileGroup.addAll([
        for (final missile in from.missiles)
          MissileComponent(
            missileSvg,
            position: missile.position,
            angle: missile.angle,
          ),
      ]);
    }
  }
}
