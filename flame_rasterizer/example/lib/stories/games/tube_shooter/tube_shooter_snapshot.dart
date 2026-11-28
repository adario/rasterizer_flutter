part of 'shooter_mode.dart';

/// The state that a game with another renderer resumes from.
///
/// It holds:
/// - the first level and the round, with the round's state and how long that
///   state has lasted;
/// - whether the round's drop flies on down a run, and the run's runner once
///   the run plays;
/// - the score, the lives and the purge;
/// - the kills, which speed up the stars;
/// - the camera and the eye;
/// - the ship, the spikes, the enemies still to come and in the tube, and the
///   shots.
typedef TubeShooterSnapshot = ({
  int firstLevel,
  int levelIndex,
  int round,
  TubeState state,
  double stateTime,
  bool hasRun,
  RunnerSnapshot? runner,
  bool dyingOnDrop,
  int score,
  int lives,
  bool purgeReady,
  double purgeLeft,
  int kills,
  double sinceSpawn,
  double pulseClock,
  Offset look,
  Offset lookFrom,
  double eyeShift,
  PlayerSnapshot player,
  List<double> spikes,
  List<SpawnSnapshot> spawns,
  List<EnemyKind> appeared,
  List<EnemySnapshot> enemies,
  List<LaneSnapshot> shots,
  List<LaneSnapshot> enemyShots,
});

/// Takes a [ShooterMode]'s snapshot, and resumes from one.
///
/// The explosions and the stars start over in the new game. So do held keys,
/// drags and taps, because the new game never saw them go down. The new game
/// plays no sounds for what the old one did, and its random picks differ from
/// those that the old one would have made.
extension TubeShooterSnapshots on ShooterMode {
  /// The state that a game with another renderer resumes from.
  TubeShooterSnapshot get snapshot => (
    firstLevel: firstLevel,
    levelIndex: _levelIndex,
    round: round,
    // For the new game, a Game Over during a run counts as the round's.
    state: isOver ? TubeState.over : _state,
    stateTime: _stateTime,
    hasRun: !isOver && _run != null,
    runner: !isOver && _state == TubeState.run ? _run!.runner.snapshot : null,
    dyingOnDrop: _dyingOnDrop,
    score: gameRef.score,
    lives: gameRef.lives,
    purgeReady: purgeReady,
    purgeLeft: _purgeLeft,
    kills: _kills,
    sinceSpawn: _sinceSpawn,
    pulseClock: _pulseClock,
    look: _look,
    lookFrom: _lookFrom,
    eyeShift: view.eyeShift,
    player: player.snapshot,
    spikes: [...spikes.lengths],
    spawns: [for (final spawn in spawns) spawn.snapshot],
    appeared: [..._appeared],
    enemies: [for (final enemy in enemies) enemy.snapshot],
    shots: [for (final shot in shots) shot.laneSnapshot],
    enemyShots: [for (final shot in enemyShots) shot.laneSnapshot],
  );

  /// Resumes [from]'s round, setting up what [_startRound] would: its tube,
  /// spikes, enemies and shots, its state, and the texts that show in it.
  void _restoreRound(TubeShooterSnapshot from) {
    _levelIndex = from.levelIndex;
    round = from.round;
    _dyingOnDrop = from.dyingOnDrop;
    gameRef.score = from.score;
    gameRef.lives = from.lives;
    purgeReady = from.purgeReady;
    _kills = from.kills;
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
    _appeared.addAll(from.appeared);
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
    // The new game doesn't resume an arrival: it starts the round instead.
    if (from.state == TubeState.arrive) {
      _startRound();
      return;
    }
    // Pause the world before setting the state, so that the state's stars
    // show at once.
    if (from.state == TubeState.over) {
      gameRef.world.timeScale = 0;
    }
    _setState(from.state);
    _stateTime = from.stateTime;
    // The drop flies on down a run if the old game's did, whatever the new
    // game's Runs knob says, so that the eye doesn't jump and the run goes
    // on. The eye is where the ship is along the run.
    if (from.hasRun) {
      _makeRun(from: from.runner);
      _run!.flown = from.eyeShift;
    }
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
