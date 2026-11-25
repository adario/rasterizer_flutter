part of 'shooter_mode.dart';

/// What a game for another renderer goes on from: the first level, the
/// round, its state and how long it has lasted, the score, the lives, the
/// purge, the camera and the eye, the ship, the spikes, the enemies still to
/// come and in the tube, and the shots.
typedef TubeShooterSnapshot = ({
  int firstLevel,
  int levelIndex,
  int round,
  TubeState state,
  double stateTime,
  bool dyingOnDrop,
  int score,
  int lives,
  bool purgeReady,
  double purgeLeft,
  double sinceSpawn,
  double pulseClock,
  Offset look,
  Offset lookFrom,
  double eyeShift,
  PlayerSnapshot player,
  List<double> spikes,
  List<SpawnSnapshot> spawns,
  List<EnemySnapshot> enemies,
  List<LaneSnapshot> shots,
  List<LaneSnapshot> enemyShots,
});

/// Takes a [ShooterMode]'s snapshot, and goes on from one.
///
/// The explosions and the stars start again in the new game, and so do the
/// keys, the drags and the taps, which the new game hasn't seen go down. The
/// new game plays no sound for what the old one did, and its random picks
/// differ from those that the old one would have made.
extension TubeShooterSnapshots on ShooterMode {
  /// What a game for another renderer goes on from.
  TubeShooterSnapshot get snapshot => (
    firstLevel: firstLevel,
    levelIndex: _levelIndex,
    round: round,
    state: _state,
    stateTime: _stateTime,
    dyingOnDrop: _dyingOnDrop,
    score: gameRef.score,
    lives: gameRef.lives,
    purgeReady: purgeReady,
    purgeLeft: _purgeLeft,
    sinceSpawn: _sinceSpawn,
    pulseClock: _pulseClock,
    look: _look,
    lookFrom: _lookFrom,
    eyeShift: view.eyeShift,
    player: player.snapshot,
    spikes: [...spikes.lengths],
    spawns: [for (final spawn in spawns) spawn.snapshot],
    enemies: [for (final enemy in enemies) enemy.snapshot],
    shots: [for (final shot in shots) shot.laneSnapshot],
    enemyShots: [for (final shot in enemyShots) shot.laneSnapshot],
  );

  /// Goes on with [from]'s round, as [_startRound] would start it: its tube,
  /// spikes, enemies and shots, its state, and the texts that show in it.
  void _restoreRound(TubeShooterSnapshot from) {
    _levelIndex = from.levelIndex;
    round = from.round;
    _dyingOnDrop = from.dyingOnDrop;
    gameRef.score = from.score;
    gameRef.lives = from.lives;
    purgeReady = from.purgeReady;
    _sinceSpawn = from.sinceSpawn;
    _pulseClock = from.pulseClock;
    _look = from.look;
    _lookFrom = from.lookFrom;
    view
      ..tube = level.tube
      ..eyeShift = from.eyeShift;
    for (final (lane, length) in from.spikes.indexed) {
      spikes.grow(lane, length);
    }
    for (final spawn in from.spawns) {
      _addSpawn(spawn.kind, spawn.at, from: spawn);
    }
    for (final enemy in from.enemies) {
      addEnemy(enemy.kind.goOnFrom(enemy));
    }
    for (final shot in from.shots) {
      final component = ShotComponent(
        lane: shot.lane,
        depth: shot.depth,
        previousDepth: shot.previousDepth,
      );
      shots.add(component);
      shotGroup.add(component);
    }
    for (final shot in from.enemyShots) {
      final component = EnemyShotComponent(
        lane: shot.lane,
        depth: shot.depth,
        previousDepth: shot.previousDepth,
      );
      enemyShots.add(component);
      shotGroup.add(component);
    }
    // The prototype's runs don't go on in the new game: the next round starts.
    if (from.state == TubeState.run) {
      _nextRound();
      return;
    }
    if (from.state == TubeState.arrive) {
      _startRound();
      return;
    }
    // Before the state, whose stars show at once in a still world.
    if (from.state == TubeState.over) {
      gameRef.world.timeScale = 0;
    }
    _setState(from.state);
    _stateTime = from.stateTime;
    switch (from.state) {
      case TubeState.zoom:
        _roundBanner.text = 'ROUND $round';
        gameRef.camera.viewport.addAll([_roundBanner, _purgeReadyText]);
      case TubeState.ready:
        gameRef.camera.viewport.add(gameRef.readyText);
      case TubeState.over:
        gameRef.camera.viewport.add(gameRef.gameOverText);
      case TubeState.play ||
          TubeState.dying ||
          TubeState.drop ||
          TubeState.run ||
          TubeState.arrive:
        break;
    }
    _purgeLeft = from.purgeLeft;
    if (_purgeLeft > 0) {
      gameRef.camera.viewport.add(_purgeText);
    }
  }
}
