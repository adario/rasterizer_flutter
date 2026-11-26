import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame_rasterizer/flame_rasterizer.dart';
import 'package:flame_rasterizer_example/commons/vector_text_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_runner/components/runner_explosion_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_runner/endless_tube.dart';
import 'package:flame_rasterizer_example/stories/games/tube_runner/runner_mode.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/bolts_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/climber_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/dot_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/enemy_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/explosion_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/lane_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/player_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/shot_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/spawn_dot_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/spikes_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/splitter_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/star_field_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/tube_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/zapper_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/level.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/shapes.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/sounds.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube_host.dart';
import 'package:flutter/foundation.dart';

part 'tube_shooter_run.dart';
part 'tube_shooter_snapshot.dart';

/// The game's states.
enum TubeState() {
  /// The tube zooms in from afar.
  zoom,

  /// READY shows until a tap or a key starts the round, or resumes it after
  /// a lost ship.
  ready,

  /// The round is on.
  play,

  /// The ship was destroyed. Next, it comes back, or the game ends.
  dying,

  /// The round's enemies are gone, and the ship drops down its lane.
  drop,

  /// With [ShooterMode.runs] on, the ship flies on from the drop, down
  /// an endless tube, by Tube Runner's rules: see [RunnerMode].
  run,

  /// The run is over: the ship flies out of its tube, onto the next round's
  /// rim.
  arrive,

  /// The game is over, and stands still until a tap, or Enter, starts a new
  /// one.
  over,
}

/// Tube Shooter's rules, and the components that play by them, under it in
/// the world, but for the stars, in the camera's backdrop, and the texts, in
/// its viewport.
///
/// In the world, the tube's axis is at the origin. The camera looks at it, or
/// at the middle of an open tube's drawing. Each round plays on the next
/// level's tube, starting from [firstLevel]. A new game after Game Over
/// starts at the round reached.
///
/// Its game, a [TubeHost] such as `TubeShooterExample`, hands it the
/// player's input, and has the score, the lives and the texts at the
/// bottom. Given the snapshot of a game with another renderer, it goes on
/// from there: see [TubeShooterSnapshots].
class ShooterMode({
  /// Which of the [levels] the first round plays.
  final int firstLevel = 0,
  TubeShooterSnapshot? from,
}) extends Component with HasGameRef<TubeHost> {
  /// How long the zoom takes, in seconds.
  static const zoomTime = 1.0;

  /// How far in front of the tube the eye starts the zoom, in tube units.
  static const zoomDistance = 12.0;

  /// How long the drop takes, in seconds.
  static const dropTime = 2.0;

  /// How long the run after [round] plays, with [runs] on, once the drop is
  /// over, in seconds of the game at Tube Runner's first speed: a minute
  /// after the first round, and [runTimeStep] more after each other. See
  /// [TubeState.run].
  static double runTime(int round) => firstRunTime + runTimeStep * (round - 1);
  static const firstRunTime = 60.0;
  static const runTimeStep = 30.0;

  /// How far a run's tube eases into its bends, and out of them, in tube
  /// units.
  static const runEase = 8.0;

  /// How long the ship takes to arrive on the next round's rim after a run,
  /// in seconds of the game.
  static const arriveTime = 4.0;

  /// How long the ship's lane takes to fade in on a run, in seconds.
  static const laneFadeTime = 0.3;

  /// How long PURGE shows once the purge is used, in seconds.
  static const purgeTime = 1.0;

  /// How close in depth a shot must be to what it hits.
  static const hitWindow = 0.04 * Tube.depth;

  /// How much a shot takes off a spike.
  static const spikeHit = 0.06 * Tube.depth;

  /// What a shot that hits a spike scores.
  static const spikeScore = 2;

  /// The snapshot that it goes on from, if any.
  final TubeShooterSnapshot? _from = from;

  /// The game's view of the tube.
  TubeView get view => gameRef.view;

  /// The game's random numbers.
  math.Random get random => gameRef.random;

  final tubeGroup = Component();
  final spawnGroup = Component(priority: 1);
  final enemyGroup = Component(priority: 1);
  final shotGroup = Component(priority: 2);
  final explosionGroup = Component(priority: 5);
  final player = PlayerComponent(from: from?.player);
  final tube = TubeComponent();
  final spikes = SpikesComponent();
  final bolts = BoltsComponent();
  late final starField = StarFieldComponent(this);

  /// The enemies in the tube, from when they're added until they're gone.
  final enemies = <EnemyComponent>{};

  /// The ship's shots in the tube.
  final shots = <ShotComponent>{};

  /// The enemies' shots in the tube.
  final enemyShots = <EnemyShotComponent>{};

  /// The enemies still to come this round, as dots at the far end, the next
  /// one last. Those arriving are among them.
  final spawns = <SpawnDotComponent>[];

  /// The kinds of the round's enemies, in the order they first came out of
  /// their dots, for its run.
  final _appeared = <EnemyKind>[];

  @visibleForTesting
  List<EnemyKind> get appeared => _appeared;

  /// Whether enemies come; tests turn it off.
  @visibleForTesting
  bool spawning = true;

  TubeState get state => _state;
  TubeState _state = TubeState.zoom;
  double _stateTime = 0;

  /// The run, from the drop it starts with to the ship's arrival on the next
  /// round's rim, with [runs] on.
  _Run? _run;

  /// What plays the run's rules, if there's a run.
  @visibleForTesting
  RunnerMode? get runner => _run?.runner;

  /// Whether the ship was destroyed on its drop, so that the next round comes
  /// rather than the same one again.
  bool _dyingOnDrop = false;

  int round = 0;
  bool purgeReady = true;

  /// The round's level.
  Level get level => levels[_levelIndex];

  /// The index of the round's level in [levels].
  int get levelIndex => _levelIndex;
  late int _levelIndex = firstLevel;

  /// Called with [levelIndex] each time a round starts.
  void Function(int levelIndex)? onLevel;

  /// Where the camera looks, in tube units.
  Offset _look = Offset.zero;

  /// Where the camera looked as the zoom began, in tube units.
  Offset _lookFrom = Offset.zero;

  /// Where the camera looks, in the world's units.
  Offset _aim = Offset.zero;

  /// The view's version at the last update.
  int _lastVersion = -1;

  /// How fast the round goes: as fast as if the game had started at the first
  /// level, so 1 on the first level's first round, and faster in each later
  /// round.
  double get pace => math.pow(roundSpeedUp, firstLevel + round - 1).toDouble();

  /// Seconds since the last enemy came, at the first round's pace.
  double _sinceSpawn = 0;

  /// Seconds into the zappers' pulse period, at the first round's pace. The
  /// pulse comes at the period's end.
  double _pulseClock = 0;

  /// Whether the zappers are pulsing, in play.
  bool get isPulsing =>
      _state == TubeState.play &&
      _pulseClock >= level.pulsePeriod - level.pulseTime;

  /// Whether the zappers flash white, just before a pulse.
  bool get isWarning {
    final pulse = level.pulsePeriod - level.pulseTime;
    return _state == TubeState.play &&
        _pulseClock < pulse &&
        _pulseClock >= pulse - level.pulseWarning;
  }

  /// The round's number, at the middle, on the zoom.
  final _roundBanner = VectorTextComponent(capHeight: TubeHost.bannerCap);

  /// PURGE READY, under the round's number on the zoom: each round recharges
  /// the purge.
  final _purgeReadyText = VectorTextComponent(
    text: 'PURGE READY',
    capHeight: TubeHost.hudCap,
    below: 1.2 * TubeHost.bannerCap,
  );

  /// PURGE, for [purgeTime] once the purge is used.
  final _purgeText = VectorTextComponent(
    text: 'PURGE',
    capHeight: TubeHost.bannerCap,
  );

  /// The seconds left before PURGE goes.
  double _purgeLeft = 0;

  /// Whether the ship moves at the player's will: in play, and in a run's.
  bool get canMove =>
      _state == TubeState.play ||
      (_state == TubeState.run && _run!.runner.canMove);

  /// Whether the ship fires at the player's will: in play, and on the drop.
  /// On a run, its runner fires.
  bool get canFire => _state == TubeState.play || _state == TubeState.drop;

  /// Whether the game waits for the player, at READY or Game Over.
  bool get isWaiting => isReady || isOver;

  /// Whether the game waits at READY, the round's or a run's.
  bool get isReady =>
      _state == TubeState.ready ||
      (_state == TubeState.run && _run!.runner.isReady);

  /// Whether the game is over, in a round or on a run, and the world stands
  /// still.
  bool get isOver =>
      _state == TubeState.over ||
      (_state == TubeState.run && _run!.runner.isOver);

  /// The Runs knob's value: whether, after a round's drop, the ship flies on
  /// down an endless tube, by Tube Runner's rules, for [runTime] of play,
  /// before it flies onto the next round's rim: see [TubeState.run]. On by
  /// default.
  bool runs = true;

  /// Does what updates would do in a moving world: makes the tube's paths
  /// again for the view, places everything on the tube, and gives the shapes
  /// their stroke and glow.
  void updateStillLines() {
    tube.update(0);
    spikes.update(0);
    bolts.update(0);
    for (final component in gameRef.world.descendants()) {
      switch (component) {
        case final LaneComponent onLane:
          onLane.place();
        case final DotComponent dot:
          dot.place();
        case final PlayerComponent ship:
          ship.place();
      }
    }
    // In the camera's backdrop, out of the world.
    for (final star in starField.stars) {
      star.place();
    }
    for (final group in [player, enemyGroup, shotGroup, explosionGroup]) {
      group.descendants().whereType<PathComponent>().forEach(
        gameRef.keepStroke,
      );
    }
  }

  /// Replaces [old], if any, with a component that fills [path], if any, in
  /// [color], and returns it.
  ///
  /// The new component goes in the tube's group, at [priority]. The renderer
  /// imports a path only once, so a changed path needs a new component.
  PathComponent? replacePath(
    PathComponent? old,
    Path? path,
    Color color, {
    int priority = 0,
  }) {
    old?.removeFromParent();
    final bounds = path?.getBounds();
    if (path == null || bounds == null || bounds.isEmpty) {
      return null;
    }
    gameRef.countPath();
    final component = gameRef.pathComponent(
      path,
      Paint()..color = color,
      position: Vector2(bounds.left, bounds.top),
      maxSize: math.max(bounds.width, bounds.height) / view.devicePixel,
      priority: priority,
      glow: gameRef.linesGlow,
    );
    tubeGroup.add(component);
    return component;
  }

  @override
  void onLoad() {
    addAll([
      tubeGroup,
      spawnGroup,
      enemyGroup,
      shotGroup,
      player,
      explosionGroup,
      tube,
      spikes,
      bolts,
    ]);
    // Under the world, out of the glow's post process.
    gameRef.camera.backdrop.add(starField);
    if (_from case final from?) {
      _restoreRound(from);
    } else {
      _nextRound();
    }
  }

  /// Applies the rules over [dt] seconds of the world's time: before the
  /// world's components move, and before [TubeComponent] makes the tube's
  /// paths for the view.
  void advance(double dt) {
    _step(dt);
    _aimCamera();
    _drawRun();
    tube.lane = _state == TubeState.play ? player.lane : null;
    // In a still world, where nothing updates, applies a change of the view,
    // such as a resize or a zoom.
    if (gameRef.world.timeScale == 0 && view.version != _lastVersion) {
      updateStillLines();
    }
    _lastVersion = view.version;
  }

  /// Places the ship as it arrives from a run, and shows the round, once the
  /// components updated, [dt] seconds after the last frame.
  void afterUpdate(double dt) {
    _placeArriving();
    if (_state == TubeState.run) {
      // The run's time in play, as Tube Runner shows its time in the tube.
      _run!.runner.afterUpdate(dt);
    } else {
      gameRef.roundText.text = 'ROUND $round';
    }
    // In real time, so that it goes in a still world too.
    if (_purgeLeft > 0) {
      _purgeLeft -= dt;
      if (_purgeLeft <= 0) {
        _purgeText.removeFromParent();
      }
    }
  }

  /// Points the camera at [_look].
  void _aimCamera() {
    final aim = _look * view.rimScale;
    if (aim != _aim) {
      _aim = aim;
      gameRef.camera.viewfinder.position.setValues(aim.dx, aim.dy);
    }
  }

  void _setState(TubeState state) {
    _state = state;
    _stateTime = 0;
    gameRef.forgetWaitPointers();
    starField.show();
  }

  /// Applies the game's rules over [dt] seconds of the world's time.
  void _step(double dt) {
    _stateTime += dt;
    switch (_state) {
      case TubeState.zoom:
        final progress = math.min(1.0, _stateTime / zoomTime);
        final left = math.pow(1 - progress, 3).toDouble();
        view.eyeShift = -zoomDistance * left;
        _look = Offset.lerp(view.tube.center, _lookFrom, left)!;
        if (progress == 1) {
          player.isVisible = true;
          _roundBanner.removeFromParent();
          _purgeReadyText.removeFromParent();
          _waitForPlayer();
        }
      case TubeState.play:
        final wasPulsing = isPulsing;
        _pulseClock = (_pulseClock + dt * pace) % level.pulsePeriod;
        if (!wasPulsing &&
            isPulsing &&
            enemies.any(
              (enemy) => enemy is ZapperComponent && enemy.isZapping,
            )) {
          gameRef.play(Sound.zap);
        }
        _spawn(dt);
        _collide();
        if (_state == TubeState.play && spawns.isEmpty && enemies.isEmpty) {
          for (final shot in [...enemyShots]) {
            discard(shot);
          }
          _setState(TubeState.drop);
          gameRef.play(Sound.drop);
          if (runs) {
            _makeRun();
          }
        }
      case TubeState.drop:
        final progress = math.min(1.0, _stateTime / dropTime);
        player.depth = view.eyeShift = _run == null
            ? Tube.depth * progress * progress
            : _run!.dropDepth(progress);
        _run?.flown = view.eyeShift;
        _collide();
        if (_state == TubeState.drop && progress == 1) {
          if (_run == null) {
            _nextRound();
          } else {
            _beginRun();
          }
        }
      case TubeState.run:
        _stepRun(dt);
      case TubeState.arrive:
        _stepArrive();
      case TubeState.dying:
        if (_stateTime >= TubeHost.respawnTime) {
          if (gameRef.lives == 0) {
            _gameOver();
          } else if (_dyingOnDrop) {
            _nextRound();
          } else {
            player.revive();
            _waitForPlayer();
          }
        }
      case TubeState.ready || TubeState.over:
        break;
    }
  }

  /// Replaces each dot that has arrived with its enemy, at the far end of its
  /// lane, and starts the next dot arriving.
  ///
  /// A dot starts arriving every level's `spawnPeriod`, while fewer than the
  /// level's `maxEnemies` are in the tube or arriving.
  void _spawn(double dt) {
    for (final spawn in spawns.where((spawn) => spawn.hasArrived).toList()) {
      spawns.remove(spawn);
      spawn.removeFromParent();
      if (!spawn.again) {
        _appeared.add(spawn.kind);
      }
      addEnemy(spawn.kind.create(lane: spawn.lane, depth: Tube.depth));
    }
    _sinceSpawn += dt * pace;
    final waiting = spawns.where((spawn) => !spawn.isArriving);
    final arriving = spawns.length - waiting.length;
    if (!spawning ||
        waiting.isEmpty ||
        enemies.length + arriving >= level.maxEnemies ||
        _sinceSpawn < level.spawnPeriod) {
      return;
    }
    _sinceSpawn = 0;
    waiting.last.arrive();
  }

  /// Adds an enemy of [kind] to come next, as a dot [at] lanes round the far
  /// end, which goes on [from] a dot in a game with another renderer, if
  /// given.
  void _addSpawn(
    EnemyKind kind,
    double at, {
    SpawnSnapshot? from,
    bool again = false,
  }) {
    final spawn = SpawnDotComponent(
      kind,
      at: at,
      from: from,
      again: again || (from?.again ?? false),
    );
    spawns.add(spawn);
    spawnGroup.add(spawn);
  }

  /// Removes all the enemies still to come.
  void clearSpawns() {
    spawnGroup.removeAll(spawns);
    spawns.clear();
  }

  /// Resolves the hits between things in the same lane that [_meet].
  ///
  /// The ship's shots shorten spikes, and destroy enemies' shots and the
  /// enemies that can be shot. An enemy's shot at the rim, an enemy as its
  /// kind does, and a spike on the drop destroy the ship in their lane.
  void _collide() {
    for (final shot in [...shots]) {
      final tip = spikes.tipOf(shot.lane);
      if (tip != null && shot.depth >= tip) {
        spikes.shorten(shot.lane, spikeHit);
        gameRef.score += spikeScore;
        gameRef.play(Sound.spike);
        discard(shot);
        continue;
      }
      final enemyShot = enemyShots
          .where((other) => other.lane == shot.lane && _meet(shot, other))
          .firstOrNull;
      if (enemyShot != null) {
        discard(enemyShot);
        discard(shot);
        continue;
      }
      final enemy = enemies
          .where(
            (other) =>
                other.canBeShot &&
                other.currentLane == shot.lane &&
                _meet(shot, other),
          )
          .firstOrNull;
      if (enemy != null) {
        discard(shot);
        destroy(enemy);
      }
    }
    for (final enemyShot in [...enemyShots]) {
      if (enemyShot.depth <= 0) {
        discard(enemyShot);
        if (enemyShot.lane == player.lane) {
          _destroyShip();
        }
      }
    }
    if (_state == TubeState.play &&
        enemies.any((enemy) => enemy.destroysShip(player.lane))) {
      _destroyShip();
    }
    final tip = spikes.tipOf(player.lane);
    if (_state == TubeState.drop && tip != null && tip <= player.depth) {
      _destroyShip();
    }
  }

  /// Returns whether [a] and [b], in the same lane, meet: within [hitWindow] in
  /// depth, or passing each other since their last update.
  static bool _meet(LaneComponent a, LaneComponent b) {
    final now = a.depth - b.depth;
    final before = a.previousDepth - b.previousDepth;
    return now.abs() <= hitWindow || now.sign != before.sign;
  }

  /// Adds [enemy] to the tube.
  void addEnemy(EnemyComponent enemy) {
    enemies.add(enemy);
    enemyGroup.add(enemy);
  }

  /// Fires a shot from the ship down [lane], from [depth].
  void fire(int lane, double depth) {
    final shot = ShotComponent(lane: lane, depth: depth);
    shots.add(shot);
    shotGroup.add(shot);
    gameRef.play(Sound.fire);
  }

  /// Fires a shot from [enemy] up its lane, if fewer than the level's
  /// `maxEnemyShots` are in the tube.
  void fireAt(EnemyComponent enemy) {
    if (_state != TubeState.play || enemyShots.length >= level.maxEnemyShots) {
      return;
    }
    final shot = EnemyShotComponent(
      lane: enemy.currentLane,
      depth: enemy.depth,
    );
    enemyShots.add(shot);
    shotGroup.add(shot);
    gameRef.play(Sound.enemyFire);
  }

  /// Returns which way an enemy at the rim in [lane] goes toward the ship: 1 or
  /// -1, or 0 in the ship's lane.
  int towardShip(int lane) {
    final tube = view.tube;
    final ahead = player.lane - lane;
    if (ahead == 0 || tube.isOpen) {
      return ahead.sign;
    }
    return ahead % tube.laneCount <= tube.laneCount ~/ 2 ? 1 : -1;
  }

  /// Replaces [splitter] with two climbers, which flip from its lane onto the
  /// lanes on either side. A climber with no lane on its side, at an open
  /// tube's end, stays in the splitter's lane.
  void split(SplitterComponent splitter) {
    if (!enemies.contains(splitter)) {
      return;
    }
    discard(splitter);
    final tube = view.tube;
    for (final side in [-1, 1]) {
      final climber = ClimberComponent(
        lane: splitter.lane,
        depth: splitter.depth,
      );
      final to = tube.neighbour(splitter.lane, side);
      if (to != null) {
        climber.flip(to, tube);
      }
      addEnemy(climber);
    }
  }

  /// Destroys [enemy] and adds its score. A splitter splits instead, unless
  /// [purged].
  void destroy(EnemyComponent enemy, {bool purged = false}) {
    if (!enemies.contains(enemy)) {
      return;
    }
    _explode(enemy, enemy.depth, rayColor: enemy.kind.color);
    gameRef.play(Sound.explosion);
    gameRef.score += enemy.kind.score;
    if (enemy is SplitterComponent && !purged) {
      split(enemy);
    } else {
      discard(enemy);
    }
  }

  /// Removes [component] from the tube.
  void discard(LaneComponent component) {
    component.removeFromParent();
    forget(component);
  }

  /// Stops tracking [component], which is gone.
  void forget(LaneComponent component) {
    switch (component) {
      case EnemyComponent():
        enemies.remove(component);
      case ShotComponent():
        shots.remove(component);
      case EnemyShotComponent():
        enemyShots.remove(component);
    }
  }

  /// Adds an explosion where [component] is, [depth] deep in the tube, turned
  /// and scaled as it is, with its flying rays in [rayColor].
  void _explode(
    PositionComponent component,
    double depth, {
    Color? color,
    Color? rayColor,
  }) {
    explosionGroup.add(
      ExplosionComponent(
        position: component.position.clone(),
        angle: component.angle,
        scale: component.scale.clone(),
        depth: depth,
        color: color ?? TubeColors.explosion,
        rayColor: rayColor,
      ),
    );
  }

  /// Destroys every enemy in the tube, and their shots, once a round.
  void purge() {
    if (_state != TubeState.play || !purgeReady) {
      return;
    }
    purgeReady = false;
    if (!_purgeText.isMounted) {
      gameRef.camera.viewport.add(_purgeText);
    }
    _purgeLeft = purgeTime;
    gameRef.play(Sound.purge);
    for (final enemy in [...enemies]) {
      destroy(enemy, purged: true);
    }
    for (final shot in [...enemyShots]) {
      discard(shot);
    }
  }

  /// Blows the ship up, fades it out, and takes a life.
  ///
  /// The enemies in the tube go back to the far end of their lanes, to come
  /// again, and all the shots go.
  void _destroyShip() {
    if (_state != TubeState.play && _state != TubeState.drop) {
      return;
    }
    _dyingOnDrop = _state == TubeState.drop;
    _endRun();
    gameRef.lives--;
    _explode(player, player.depth, color: TubeColors.ship);
    gameRef.play(Sound.crash);
    player.fadeOut();
    for (final spawn in spawns) {
      spawn.wander();
    }
    for (final enemy in [...enemies]) {
      _addSpawn(enemy.kind, enemy.currentLane + 0.5, again: true);
      discard(enemy);
    }
    for (final shot in [...shots, ...enemyShots]) {
      discard(shot);
    }
    _setState(TubeState.dying);
  }

  /// Starts the next round on the next level's tube, or the first round on
  /// the round's level, [arriving] from a run if so.
  void _nextRound({bool arriving = false}) {
    if (round > 0) {
      _levelIndex = (_levelIndex + 1) % levels.length;
    }
    round++;
    _startRound(arriving: arriving);
  }

  /// Starts the round on its level's tube.
  ///
  /// The round starts with its enemies at random round the far end, no
  /// spikes, the purge ready, and the ship on the tube's bottom lane. The tube
  /// zooms in through the stars, with the ship hidden until the zoom ends.
  ///
  /// [arriving] from a run, the ship flies onto the rim instead, at the step
  /// nearest its angle round the axis: see [_beginArrive].
  void _startRound({bool arriving = false}) {
    final from = view.tube;
    view.tube = level.tube;
    _lookFrom = _look;
    spikes.clear();
    clearSpawns();
    _appeared.clear();
    final kinds = [
      for (var i = 0; i < level.climbers; i++) EnemyKind.climber,
      for (var i = 0; i < level.splitters; i++) EnemyKind.splitter,
      for (var i = 0; i < level.seeders; i++) EnemyKind.seeder,
      for (var i = 0; i < level.zappers; i++) EnemyKind.zapper,
      for (var i = 0; i < level.edgeWalkers; i++) EnemyKind.edgeWalker,
    ]..shuffle(random);
    for (final kind in kinds) {
      _addSpawn(kind, view.tube.laneCount * random.nextDouble());
    }
    purgeReady = true;
    _sinceSpawn = level.spawnPeriod;
    _pulseClock = 0;
    for (final shot in [...shots, ...enemyShots]) {
      discard(shot);
    }
    player.revive();
    if (arriving) {
      player.step = _Run.nearestStep(from, player.step, view.tube);
      // The eye goes on as fast, with the rim ahead now.
      starField.shiftEye(-_run!.rim);
      view.eyeShift = _run!.flown - _run!.rim;
    } else {
      player
        ..startOn(view.tube)
        ..isVisible = false;
      view.eyeShift = -zoomDistance;
    }
    _roundBanner.text = 'ROUND $round';
    gameRef.camera.viewport.addAll([_roundBanner, _purgeReadyText]);
    _setState(arriving ? TubeState.arrive : TubeState.zoom);
    gameRef.play(Sound.zoom);
    onLevel?.call(_levelIndex);
  }

  /// Shows READY, until a tap or a key.
  void _waitForPlayer() {
    gameRef.camera.viewport.add(gameRef.readyText);
    _setState(TubeState.ready);
  }

  /// Starts the round, or resumes it after a lost ship. No tap before this
  /// counts toward a double tap.
  void _beginPlay() {
    gameRef.readyText.removeFromParent();
    gameRef.forgetTaps();
    _setState(TubeState.play);
  }

  /// Stops the world, whatever the game's speed is, and shows Game Over
  /// until a tap or Enter.
  void _gameOver() {
    gameRef.world.timeScale = 0;
    _setState(TubeState.over);
    player.isVisible = false;
    gameRef.camera.viewport.add(gameRef.gameOverText);
  }

  /// Starts a new game in this one: no enemies, shots or explosions, a score
  /// of 0, all lives, the round that the last game reached, at its pace, and
  /// the world at the game's speed.
  void _newGame() {
    for (final enemy in [...enemies]) {
      discard(enemy);
    }
    explosionGroup.removeAll(explosionGroup.children.toList());
    gameRef.score = 0;
    gameRef.lives = TubeHost.startLives;
    gameRef.gameOverText.removeFromParent();
    gameRef.world.timeScale = gameRef.speed;
    _endRun();
    _startRound();
  }

  /// Moves the ship [lanes] round the tube: the runner's, on a run.
  void moveShipBy(double lanes) {
    if (_state == TubeState.run) {
      _run!.runner.moveShipBy(lanes);
    } else {
      player.moveBy(lanes);
    }
  }

  /// Ends a wait: starts a new game once it's over, on a run too, or else
  /// the round, or the run's play.
  void endWait() {
    if (isOver) {
      _newGame();
    } else if (_state == TubeState.run) {
      _run!.runner.endWait();
    } else {
      _beginPlay();
    }
  }

  /// Makes the ship fire while the player fires.
  void onFiringChanged() {
    if (gameRef.isFiring) {
      player.beginFire();
    } else {
      player.stopFire();
    }
  }
}

/// A component under a [ShooterMode], which plays by its rules.
mixin InShooterMode on Component {
  /// The mode that it's under, or was under when it [findShooter].
  ShooterMode get shooter => _shooter ??= findParent<ShooterMode>()!;
  ShooterMode? _shooter;

  /// Finds the mode that it's under, so that [shooter] is still its mode
  /// once it's gone from it, as when it finishes loading after a purge.
  void findShooter() => _shooter ??= findParent<ShooterMode>();
}
